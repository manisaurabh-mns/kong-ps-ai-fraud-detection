# Fraud Design

## 1. Purpose

The Fraud API provides an internal, secure, and scalable fraud decisioning capability
for a global fintech platform. It supports real‑time fraud risk assessment for:

- Account information access
- Payment initiation
- Transaction history access

The API leverages deterministic rules and AI/LLM‑based reasoning while ensuring that
the underlying LLM is never directly exposed to consumers.

---

## 2. Business Requirements

### 2.1 Functional Requirements

- Analyze transactions and access requests for fraud risk
- Support fraud checks for synchronous API flows
- Return clear outcomes:
  - **ALLOW**
  - **CHALLENGE**
  - **BLOCK**
- Provide explainable fraud reasons for:
  - Audit
  - Investigation
  - Regulatory review
- Support near real‑time decisioning (sub‑second latency)

---

### 2.2 Non‑Functional Requirements

- High availability and horizontal scalability
- Low latency suitable for payment authorization flows
- Secure‑by‑design (Zero Trust)
- Compliance alignment with:
  - PSD2
  - Open Banking
- Full auditability and traceability of all decisions

---

## 3. Scope

### 3.1 In Scope

- Transaction fraud analysis
- Behavioral anomaly detection
- High‑value payment risk checks
- Account takeover (ATO) risk assessment
- Open Banking / partner misuse detection
- Fraud explanation generation using AI

---

### 3.2 Out of Scope

- End‑user authentication (handled upstream)
- Chargeback lifecycle management
- Case management UI
- Manual fraud review workflows

---

## 4. Target Consumers

| Consumer Type     | Description                                  |
|------------------|----------------------------------------------|
| Mobile Apps       | First‑party customer applications            |
| Fintech Partners  | Third‑party Open Banking consumers            |
| Internal Systems  | Analytics, monitoring, and reporting systems |

> Consumers never call the Fraud API directly.  
> All access is mediated via Kong Gateway.

---

## 5. High‑Level Architecture

```text
Client → Kong Gateway → Business APIs → Fraud API → LLM Provider
