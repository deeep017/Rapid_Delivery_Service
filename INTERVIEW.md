# 🚀 Rapid Delivery Service - Software Engineering Interview Guide

This document serves as a comprehensive guide for technical interviews, detailing the system architecture, technology choices, trade-offs, and engineering decisions behind the Rapid Delivery Service.

---

## 1. The Elevator Pitch (What it is & How it works)
**Rapid Delivery Service** is a highly scalable, geo-aware Quick Commerce platform (similar to Zepto or Blinkit) built on an event-driven microservices architecture. 

When a customer opens the app, the system instantly identifies their location and searches for the nearest warehouse within a 30km radius using **OpenSearch**. It cross-references this with real-time inventory cached in **Redis**. When an order is placed, it is securely transaction-logged in **PostgreSQL** by the Order Service, which then emits an event to a message broker (**Kafka** locally, **AWS SQS** in production). An asynchronous **Fulfillment Worker** consumes this event to process the order and decrement stock atomically. The entire infrastructure is orchestrated via **Kubernetes** and managed using **Terraform** as Infrastructure-as-Code (IaC).

---

## 2. What We USED and WHY (Technology Stack)

### Backend Services & Framework
* **Python & FastAPI:** 
  * *Why:* FastAPI provides out-of-the-box asynchronous support (ASGI), incredibly fast execution (comparable to NodeJS/Go in some workloads), and automatic Swagger documentation which is essential for rapid microservice development.

### Databases & Caching
* **PostgreSQL:**
  * *Why:* Used as the primary source of truth for Orders. Financial and order data require strong ACID compliance to ensure data integrity during concurrent transactions.
* **Redis:**
  * *Why:* Used for ultra-fast, real-time inventory caching. In quick-commerce, read operations (checking stock) outnumber writes 10:1. Redis also allows for atomic operations (like decrementing stock) to prevent race conditions and overselling.
* **OpenSearch:**
  * *Why:* Used specifically for its `_geo_distance` sorting capabilities. It allows the system to instantly rank warehouses by distance from the user's latitude/longitude and apply a strict 30km cutoff radius.

### Event Streaming & Message Brokers
* **Apache Kafka (Local) / AWS SQS (Production):**
  * *Why:* Used to decouple the Order Service from the Fulfillment Service. When traffic spikes (e.g., a flash sale), the Order Service just writes to the DB and drops a message in the queue. The queue acts as a shock absorber so the Fulfillment Worker isn't overwhelmed, eliminating cascading failures.

### Infrastructure & DevOps
* **Docker & Kubernetes (K3s):**
  * *Why:* Ensures environmental consistency (it works on my machine = it works in prod). Kubernetes handles auto-healing, restart policies, and horizontal scaling of individual microservices.
* **Terraform:**
  * *Why:* Infrastructure as Code (IaC). Allows one-click, repeatable deployment of EC2 instances, RDS databases, and SQS queues without clicking through the AWS console.

### Frontend
* **Flutter:**
  * *Why:* A single codebase compiles to native apps for Mobile (iOS/Android) and Web. Features a dual-role architecture (Buyer interface and Warehouse Manager interface) in one application.

---

## 3. What We DID NOT USE and WHY (Engineering Trade-offs)

### ❌ We did NOT use a Monolithic Architecture
* **Why Not:** In e-commerce, the `Availability/Catalog` service gets hit with 10x-100x more traffic than the `Order` service (browsing vs. buying). A monolith forces us to scale the entire application. Microservices allow us to independently scale up the Availability Service while keeping the Order Service smaller.

### ❌ We did NOT use MongoDB (NoSQL) for Orders
* **Why Not:** While NoSQL is great for flexible schemas (like logging or catalogs), order processing demands strict relational integrity. Eventual consistency (a hallmark of distributed NoSQL) could result in lost orders, duplicate payments, or broken foreign keys between a customer and their order history. We strictly stuck to PostgreSQL for ACID guarantees.

### ❌ We did NOT use PostGIS (PostgreSQL Geo-Extension) for Warehouse Routing
* **Why Not:** We could have used Postgres to calculate distances. However, OpenSearch is heavily optimized for search-heavy read operations and distributed computing. By offloading geo-queries to OpenSearch, we remove expensive computational load from our primary transactional database (Postgres), protecting the system's ability to take orders.

### ❌ We did NOT use Synchronous REST API calls for Fulfillment
* **Why Not:** If the Order Service made a direct HTTP POST call to the Fulfillment Service (`Order -> Fulfillment`), it creates **Tight Coupling**. 
  * If the Fulfillment Service goes down, the Order Service would fail to place the order.
  * *Solution:* By using Kafka/SQS, if the Fulfillment worker crashes, the queue simply stores the pending orders. Once the worker restarts, it picks up right where it left off. No orders are lost.

### ❌ We did NOT use Server-Side Rendering (e.g., Django Templates, Next.js)
* **Why Not:** A Quick Commerce app requires real-time, highly interactive UI components (live maps, instant cart updates, active timers). A native SPA (Single Page Application) approach via Flutter consumes JSON APIs directly, vastly reducing the payload size over the network compared to transmitting HTML over the wire.

---

## 4. Key Interview Discussion Points (Bottlenecks & Scaling)

If asked: *"How does this system scale? Where is the bottleneck?"*

1. **Current Bottleneck Identified:** During load testing, the read operations (Availability/Products) easily hit **100+ req/sec** thanks to Redis/OpenSearch. However, write operations (Orders) maxed out around **17 req/sec**.
2. **The Fix:** The bottleneck is the PostgreSQL write-lock and synchronous indexing. To scale further:
   * Implement connection pooling (e.g., PgBouncer).
   * Separate read/write replicas (Master instance for placing orders, read replicas for fetching order history).
3. **Handling Concurrency (Overselling):** If 5 people try to buy the last Apple simultaneously, Redis `DECR` combined with Postgres row-level locking (`SELECT ... FOR UPDATE`) ensures only the first request succeeds, while the rest gracefully fail.
