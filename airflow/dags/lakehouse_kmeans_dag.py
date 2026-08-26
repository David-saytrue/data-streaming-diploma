"""Airflow DAG: K-Means on Gold Parquet in MinIO."""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "adventureworks",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}

with DAG(
    dag_id="lakehouse_customer_kmeans",
    default_args=default_args,
    description="K-Means clustering on Gold fact_sales_order_line (MinIO Parquet)",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["lakehouse", "minio", "kmeans", "analytics"],
) as dag:
    run_kmeans = BashOperator(
        task_id="kmeans_customers_minio",
        bash_command="python /opt/airflow/analytics/kmeans_customers.py",
        env={
            "MINIO_ENDPOINT": "http://minio:9000",
            "MINIO_ACCESS_KEY": "admin",
            "MINIO_SECRET_KEY": "adminpassword",
            "MINIO_BUCKET": "lakehouse-admin",
            "KMEANS_K": "3",
        },
    )
