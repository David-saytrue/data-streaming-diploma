# როგორ მუშაობს ყველაფერი — სრული ახსნა

ეს ფაილი არის შენი „შპარგალკა“: event, topic, ფორმატი, Flink, Iceberg, MinIO.

---

## 1. საერთო სურათი ერთი წინადადებით

PostgreSQL-ში ცვლილება ხდება → Debezium იჭერს → Kafka topic-ში წერს JSON event-ს → Flink კითხულობს და ამუშავებს → Iceberg ცხრილებში წერს → ფაილები ფიზიკურად MinIO-შია → Presto/Metabase კითხულობს.

```text
Postgres (ცხრილი)
   ↓  WAL ცვლილება
Debezium (CDC)
   ↓  JSON event
Kafka topic (მაგ. aw.sales.sales_order_header)
   ↓  Flink კითხულობს
Apache Flink SQL
   ↓  Bronze + Gold
Apache Iceberg (ლოგიკური ცხრილები)
   ↓  Parquet + metadata
MinIO (ფიზიკური ფაილები)
   ↓
Presto / Metabase
```

---

## 2. რა არის Event?

**Event** = ერთი ცვლილების შეტყობინება.

მაგალითი: Postgres-ში გააკეთე ახალი შეკვეთა (INSERT).  
Debezium ამას აქცევს ერთ (ან რამდენიმე) event-ად და Kafka-ში აგზავნის.

Event-ში ჩვეულებრივ წერია:
- რა ცხრილში მოხდა ცვლილება
- რა ოპერაცია იყო: `c` = create/insert, `u` = update, `d` = delete
- რა მონაცემი იყო **before** (წინ) და **after** (შემდეგ)
- როდის მოხდა (timestamp), რომელი LSN/tx და სხვ.

შენთან ფორმატი არის **Debezium JSON Envelope**.

მაგალითი (გამარტივებული):

```json
{
  "payload": {
    "before": null,
    "after": {
      "sales_order_id": 14,
      "customer_id": 1,
      "currency_code": "GEL",
      "total_due": "24.9800"
    },
    "source": {
      "db": "adventureworks",
      "schema": "sales",
      "table": "sales_order_header",
      "connector": "postgresql"
    },
    "op": "c",
    "ts_ms": 1783592764390
  }
}
```

ანუ:
- `op: "c"` → ახალი ჩანაწერი
- `after` → ახალი მნიშვნელობები
- `before: null` → INSERT-ზე წინა მდგომარეობა არ არსებობს

---

## 3. რა არის Topic და სად არის?

**Topic** = Kafka-ში თემა/არხი, სადაც ერთი ტიპის event-ები ინახება.

შენთან Debezium ქმნის topic-ს ასე:

`aw.<schema>.<table>`

ანუ prefix არის `aw` (`topic.prefix=aw`).

### შენი 10 topic:

| Postgres ცხრილი | Kafka topic |
|-----------------|-------------|
| person.person | `aw.person.person` |
| production.product_category | `aw.production.product_category` |
| production.product_subcategory | `aw.production.product_subcategory` |
| production.product | `aw.production.product` |
| sales.sales_territory | `aw.sales.sales_territory` |
| sales.currency | `aw.sales.currency` |
| sales.customer | `aw.sales.customer` |
| sales.sales_person | `aw.sales.sales_person` |
| sales.sales_order_header | `aw.sales.sales_order_header` |
| sales.sales_order_detail | `aw.sales.sales_order_detail` |

**სად არის ფიზიკურად?**  
Kafka broker-ში (Docker კონტეინერი, პორტი `:9092`).  
Zookeeper (`:2181`) მხოლოდ Kafka-ს კოორდინაციას უკეთებს (metadata/broker health), event-ებს თვითონ არ ინახავს.

---

## 4. რა ფორმატით გადადის მონაცემი ეტაპებზე?

| ეტაპი | ფორმატი / სახე |
|-------|----------------|
| PostgreSQL შიგნით | რელაციური რიგები (ცხრილები) |
| WAL | Postgres-ის binary/log ცვლილებები |
| Debezium → Kafka | **JSON** (Debezium envelope), decimals = **string** |
| Kafka-ში ინახება | იგივე JSON message-ები topic-ებში |
| Flink კითხულობს | `format = debezium-json` |
| Flink ამუშავებს | შიდა row/record (SQL ტიპები) |
| Iceberg/MinIO-ში იწერება | **Parquet** ფაილები + Iceberg **metadata** |
| Presto/Metabase კითხულობს | SQL → იგივე Iceberg/Parquet |

### მნიშვნელოვანი კონვერტაციები Flink-ში
Debezium-იდან მოდის უცნაური ტიპები, Flink ასწორებს:

- `DECIMAL` მოდის **STRING**-ად → Flink აკეთებს `CAST(... AS DECIMAL)`
- `TIMESTAMP` მოდის **BIGINT microseconds**-ად → `TO_TIMESTAMP_LTZ(.../1000, 3)`
- `DATE` მოდის **INT days**-ად → `TO_DATE(...)`

ამიტომ Flink მხოლოდ „გადამტანი“ არ არის — ტიპებსაც ასწორებს.

---

## 5. რას აკეთებს თითო კომპონენტი?

### PostgreSQL
OLTP წყარო. აქ კეთდება INSERT/UPDATE/DELETE.  
CDC-ისთვის ჩართულია `wal_level=logical`.

### Debezium
CDC კონექტორი.  
კითხულობს WAL-ს `pgoutput`-ით და ქმნის Kafka event-ებს.  
არ ამუშავებს ანალიტიკას — მხოლოდ **ცვლილებას იჭერს და აგზავნის**.

### Kafka
Event bus / ბუფერი.  
Debezium წერს, Flink კითხულობს.  
თუ Flink ცოტა დააგვიანა — event topic-ში რჩება.

### Zookeeper
Kafka-ს კოორდინატორი (broker registration, metadata).  
შენს სტეკში სავალდებულოა, რადგან Debezium Kafka image Zookeeper-ზეა აგებული.

### Apache Flink
Streaming ძრავა — **მთავარი დამუშავება**.

რას აკეთებს:
1. კითხულობს 10 Kafka topic-ს
2. parse აკეთებს `debezium-json`-ს
3. ასწორებს ტიპებს
4. წერს **Bronze** ცხრილებს (ნედლი სარკეები)
5. აკეთებს join-ებს და ქმნის **Gold** star schema-ს
6. checkpoint-ით ინარჩუნებს exactly-once / recovery

ფაილი: `flink_job.sql`  
Job სახელი: `adventureworks-cdc-lakehouse`  
Checkpoint: `10s`, mode: `EXACTLY_ONCE`

### Apache Iceberg
ცხრილის **ფორმატი/სტანდარტი** object storage-ზე.

Iceberg არ არის ცალკე „ბაზა როგორც Postgres“.  
იგი ამბობს:
- როგორ გამოიყურება ცხრილი
- სად არის ფაილები
- რომელი snapshot არის მიმდინარე
- როგორ გაკეთდეს ACID commit, upsert, time travel

შენთან:
- format-version = 2
- `write.upsert.enabled = true` (CDC update/delete-ისთვის)

### MinIO
ფიზიკური storage (S3-compatible).  
აქ ინახება:
- `iceberg_data/` → Bronze/Gold Parquet + Iceberg metadata
- `analytics/` → K-Means შედეგები

Bucket: `lakehouse-admin`  
Console: http://localhost:9001

### Presto
SQL query engine Iceberg-ზე.  
კითხულობს იმავე MinIO/Iceberg მონაცემს.

### Metabase
BI დეშბორდი Presto-ს გავლით.  
გრაფიკები/KPI — არ აკეთებს CDC-ს.

### Airflow + Python K-Means
ცალკე batch ფენა.  
Airflow გაუშვებს Python-ს → კითხულობს Gold Parquet-ს MinIO-დან → K-Means → წერს `analytics/customer_clusters/`.

---

## 6. Flink უფრო დეტალურად

Flink-ში სამი სახის „ცხრილია“:

### A) Kafka source ცხრილები
მაგ: `kafka_person`, `kafka_sales_order_header`  
ესენი Kafka topic-ებს უკავშირდება (`debezium-json`).

### B) Bronze Iceberg ცხრილები
მაგ: `bronze.br_person`, `bronze.br_sales_order_detail`  
1:1 სარკე წყაროსთან (გაწმენდილი ტიპებით).

### C) Gold Iceberg ცხრილები
- dimensions: `dim_customer`, `dim_product`, `dim_territory`, ...
- fact: `fact_sales_order_line`

მაგალითი Gold-ში:
- `dim_customer` = customer ⋈ person ⋈ territory
- `fact_sales_order_line` = order_header ⋈ order_detail + გამოთვლილი `line_total`

ყველა INSERT ერთად ეშვება:

`EXECUTE STATEMENT SET ... END`

ანუ ერთი unified streaming job.

---

## 7. რა არის Iceberg? (დაცვისთვის მარტივად)

**Iceberg = open table format.**

წარმოიდგინე:
- MinIO = დისკი/ფოლდერები (ფაილები)
- Parquet = თავად მონაცემის ფაილები
- Iceberg = „კატალოგი + წესები“, რომ ეს ფაილები ცხრილივით მოიქცნენ

Iceberg გვაძლევს:
- ACID commit-ებს
- snapshot-ებს
- time travel-ს (`FOR VERSION AS OF` / snapshot)
- schema evolution-ს
- upsert/delete-ს (v2)

ამიტომ ამბობენ **Lakehouse**:  
data lake-ის storage (MinIO) + warehouse-ის ცხრილური ქცევა (Iceberg).

---

## 8. Checkpoint vs ჩაწერა (მოკლედ)

- **ვინ წერს Iceberg/MinIO-ში?** → Flink
- **Checkpoint რას აკეთებს?** → Flink state/offset-ის შენახვა recovery-სთვის
- Iceberg sink ხშირად commit-ს checkpoint-თან აკავშირებს, ამიტომ მონაცემი „საბოლოოდ ხილული“ ხშირად checkpoint-ის შემდეგ ჩანს
- ამიტომ latency ≈ 9–14 წამი როცა checkpoint=10s — ნორმალურია

---

## 9. ერთი INSERT-ის გზა (დამახსოვრე ეს)

1. `INSERT` Postgres-ში (`sales_order_header` + `sales_order_detail`)
2. იწერება WAL-ში
3. Debezium კითხულობს და ქმნის JSON event-ებს
4. იწერება topic-ებში:
   - `aw.sales.sales_order_header`
   - `aw.sales.sales_order_detail`
5. Flink კითხულობს ორივე topic-ს
6. წერს Bronze-ს (`br_*`)
7. აკეთებს join-ს და წერს Gold fact-ს (`fact_sales_order_line`)
8. ფაილები ეშვება MinIO-ზე (`iceberg_data/.../*.parquet`)
9. Presto/Metabase ხედავს ახალ რიგს (~10–14 წამში)

---

## 10. დაცვაზე 30-წამიანი ვერსია

> Event არის ერთი ცვლილების JSON შეტყობინება.  
> Topic არის Kafka-ში არხი თითო ცხრილისთვის, მაგალითად `aw.sales.sales_order_header`.  
> Debezium CDC-ით ქმნის ამ event-ებს, Kafka ინახავს, Flink კითხულობს და ქმნის Bronze/Gold Iceberg ცხრილებს.  
> Iceberg არის table format, ხოლო MinIO — ფიზიკური S3 storage, სადაც Parquet ფაილებია.  
> Presto და Metabase ამაზე აკეთებენ ანალიტიკას.

---

## 11. სწრაფი ლექსიკონი

| ტერმინი | მნიშვნელობა |
|---------|-------------|
| Event | ერთი ცვლილების შეტყობინება |
| Topic | Kafka არხი event-ებისთვის |
| CDC | Change Data Capture — მხოლოდ ცვლილებების კოპირება |
| WAL | Postgres-ის ცვლილებების ლოგი |
| Debezium JSON | Event-ის ფორმატი Kafka-ში |
| Flink | Streaming დამუშავება |
| Bronze | ნედლი CDC სარკე |
| Gold | ანალიტიკური star schema |
| Iceberg | ცხრილის ფორმატი lake-ზე |
| Parquet | სვეტური ფაილის ფორმატი |
| MinIO | S3-compatible object storage |
| Checkpoint | Flink state snapshot / recovery წერტილი |
