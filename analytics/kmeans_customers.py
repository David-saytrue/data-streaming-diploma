#!/usr/bin/env python3
"""
Customer K-Means clustering on Gold layer data stored in MinIO.

Reads Parquet files from Iceberg Gold fact table, aggregates per customer,
runs K-Means, writes results back to MinIO.

Env vars (defaults match docker-compose):
  MINIO_ENDPOINT   http://minio:9000
  MINIO_ACCESS_KEY admin
  MINIO_SECRET_KEY adminpassword
  MINIO_BUCKET     lakehouse-admin
  ICEBERG_PREFIX   iceberg_data/gold/fact_sales_order_line/data
  OUTPUT_PREFIX    analytics/customer_clusters
  KMEANS_K         3
"""

from __future__ import annotations

import io
import json
import os
import sys
from datetime import datetime, timezone

import boto3
import pandas as pd
from botocore.client import Config
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def s3_client():
    endpoint = env("MINIO_ENDPOINT", "http://minio:9000")
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=env("MINIO_ACCESS_KEY", "admin"),
        aws_secret_access_key=env("MINIO_SECRET_KEY", "adminpassword"),
        config=Config(signature_version="s3v4"),
        region_name="us-east-1",
    )


def list_parquet_keys(client, bucket: str, prefix: str) -> list[str]:
    keys: list[str] = []
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key.endswith(".parquet"):
                keys.append(key)
    return keys


def read_parquet_keys(client, bucket: str, keys: list[str]) -> pd.DataFrame:
    frames = []
    for key in keys:
        body = client.get_object(Bucket=bucket, Key=key)["Body"].read()
        frames.append(pd.read_parquet(io.BytesIO(body)))
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def build_customer_features(fact: pd.DataFrame) -> pd.DataFrame:
    if fact.empty:
        return fact

    numeric = fact.copy()
    numeric["line_total"] = pd.to_numeric(numeric["line_total"], errors="coerce")
    numeric = numeric.dropna(subset=["line_total", "customer_id"])

    agg = (
        numeric.groupby("customer_id")
        .agg(
            order_lines=("sales_order_detail_id", "count"),
            total_revenue=("line_total", "sum"),
            avg_line_value=("line_total", "mean"),
            unique_products=("product_id", "nunique"),
        )
        .reset_index()
    )
    return agg


def run_kmeans(features: pd.DataFrame, k: int) -> pd.DataFrame:
    feature_cols = ["order_lines", "total_revenue", "avg_line_value", "unique_products"]
    x = features[feature_cols].astype(float)
    scaled = StandardScaler().fit_transform(x)

    model = KMeans(n_clusters=k, random_state=42, n_init=10)
    labels = model.fit_predict(scaled)

    out = features.copy()
    out["cluster"] = labels
    out["cluster_label"] = out["cluster"].map(lambda c: f"cluster_{c}")
    return out


def write_results(client, bucket: str, prefix: str, df: pd.DataFrame) -> str:
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    parquet_key = f"{prefix}/run_ts={ts}/customer_clusters.parquet"
    csv_key = f"{prefix}/run_ts={ts}/customer_clusters.csv"

    pq_buf = io.BytesIO()
    df.to_parquet(pq_buf, index=False)
    pq_buf.seek(0)
    client.put_object(Bucket=bucket, Key=parquet_key, Body=pq_buf.getvalue())

    csv_buf = io.BytesIO()
    df.to_csv(csv_buf, index=False)
    csv_buf.seek(0)
    client.put_object(Bucket=bucket, Key=csv_key, Body=csv_buf.getvalue())

    return parquet_key


def main() -> int:
    bucket = env("MINIO_BUCKET", "lakehouse-admin")
    prefix = env("ICEBERG_PREFIX", "iceberg_data/gold/fact_sales_order_line/data")
    output_prefix = env("OUTPUT_PREFIX", "analytics/customer_clusters")
    k = int(env("KMEANS_K", "3"))

    print("=" * 60)
    print("K-Means customer clustering (Gold fact @ MinIO)")
    print(f"  bucket : {bucket}")
    print(f"  source : {prefix}")
    print(f"  k      : {k}")
    print("=" * 60)

    client = s3_client()
    keys = list_parquet_keys(client, bucket, prefix)
    print(f"Found {len(keys)} Parquet file(s) under Gold fact table.")

    if not keys:
        print("ERROR: No Parquet data. Run Flink pipeline first (demo-pipeline.ps1).")
        return 1

    fact = read_parquet_keys(client, bucket, keys)
    print(f"Loaded {len(fact)} fact rows.")

    features = build_customer_features(fact)
    if len(features) < k:
        print(f"ERROR: Need at least {k} customers for K={k}, got {len(features)}.")
        return 1

    result = run_kmeans(features, k)
    out_key = write_results(client, bucket, output_prefix, result)

    summary = (
        result.groupby("cluster")
        .agg(customers=("customer_id", "count"), avg_revenue=("total_revenue", "mean"))
        .reset_index()
    )

    print("\nCluster summary:")
    print(summary.to_string(index=False))
    print("\nSample rows:")
    print(result.head(10).to_string(index=False))
    print(f"\nSaved: s3://{bucket}/{out_key}")

    report = {
        "customers": int(len(result)),
        "k": k,
        "output": f"s3://{bucket}/{out_key}",
        "clusters": summary.to_dict(orient="records"),
    }
    print("\nJSON report:")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
