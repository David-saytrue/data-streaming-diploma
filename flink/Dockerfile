
FROM flink:1.17.2-java11

# Set the versions for our streaming connectors and dependencies
ENV ICEBERG_VERSION=1.4.3
ENV HADOOP_VERSION=3.3.4
ENV FLINK_VERSION=1.17.2
ENV FLINK_MAJOR_VERSION=1.17
ENV HADOOP_CONF_DIR=/opt/flink/conf

# Download all required libraries. We use curl -fSL to fail correctly on HTTP 404 errors.
# 1. Iceberg runtime
# 2. Flink SQL Kafka connector 
# 3. Hadoop Client API and Runtime (shaded Hadoop core)
# 4. Commons-Logging (required by Hadoop Configuration internals)
# 5. Hadoop AWS and AWS SDK for S3 support
# 6. Flink JSON formatter (supports Debezium CDC natively)
RUN mkdir -p /opt/flink/lib && \
    curl -fSLo /opt/flink/lib/iceberg-flink-runtime-${FLINK_MAJOR_VERSION}-${ICEBERG_VERSION}.jar https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-${FLINK_MAJOR_VERSION}/${ICEBERG_VERSION}/iceberg-flink-runtime-${FLINK_MAJOR_VERSION}-${ICEBERG_VERSION}.jar && \
    curl -fSLo /opt/flink/lib/flink-sql-connector-kafka-${FLINK_VERSION}.jar https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/${FLINK_VERSION}/flink-sql-connector-kafka-${FLINK_VERSION}.jar && \
    curl -fSLo /opt/flink/lib/hadoop-client-api-${HADOOP_VERSION}.jar https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-api/${HADOOP_VERSION}/hadoop-client-api-${HADOOP_VERSION}.jar && \
    curl -fSLo /opt/flink/lib/hadoop-client-runtime-${HADOOP_VERSION}.jar https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/${HADOOP_VERSION}/hadoop-client-runtime-${HADOOP_VERSION}.jar && \
    curl -fSLo /opt/flink/lib/commons-logging-1.2.jar https://repo1.maven.org/maven2/commons-logging/commons-logging/1.2/commons-logging-1.2.jar && \
    curl -fSLo /opt/flink/lib/hadoop-aws-${HADOOP_VERSION}.jar https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar && \
    curl -fSLo /opt/flink/lib/aws-java-sdk-bundle-1.12.262.jar https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar && \
    curl -fSLo /opt/flink/lib/flink-json-${FLINK_VERSION}.jar https://repo1.maven.org/maven2/org/apache/flink/flink-json/${FLINK_VERSION}/flink-json-${FLINK_VERSION}.jar && \
    curl -fSLo /opt/flink/lib/iceberg-aws-${ICEBERG_VERSION}.jar https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws/${ICEBERG_VERSION}/iceberg-aws-${ICEBERG_VERSION}.jar && \
    curl -fSLo /opt/flink/lib/bundle-2.20.18.jar https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.20.18/bundle-2.20.18.jar

# Flink provides native S3 filesystem plugins internally. We must copy them to the plugins directory.
RUN mkdir -p /opt/flink/plugins/s3-fs-presto && \
    cp /opt/flink/opt/flink-s3-fs-presto-${FLINK_VERSION}.jar /opt/flink/plugins/s3-fs-presto/

# Copy Hadoop config so S3A picks up MinIO endpoint
COPY core-site.xml /opt/flink/conf/core-site.xml
