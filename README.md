# Data Streaming Architecture (Дипломная работа)

Проект по построению масштабируемой потоковой инфраструктуры для интернет-магазина.

**Текущий слой**: PostgreSQL -> Debezium (CDC) -> Apache Kafka.

## Как локально запустить

1. Поднять инфраструктуру:
   ```powershell
   docker-compose up -d
   ```
2. Зарегистрировать коннектор Debezium для трекинга изменений базы:
   ```powershell
   curl.exe -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" http://localhost:8083/connectors/ -d "@register-connector.json"
   ```
3. Проверить события потоковой передачи в Kafka:
   ```powershell
   docker exec -it data-streaming-diploma-kafka-1 /kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic shop.shop.orders --from-beginning
   ```

## Что будет дальше
- Добавление Apache Flink для потоковой обработки
- Data Lake (МinIO + Apache Iceberg)
- Trino для распределенных SQL-запросов к Data Lake
