# Transaction with Fraud Detection — Request Flow

## Entry Point (Demo vs Production)

| Mode | How clients reach Kong | Config |
|------|------------------------|--------|
| Demo | `kubectl port-forward svc/kong-dp 8000:80 -n kong` | No NLB provisioned |
| Production | AWS NLB DNS → Kong proxy service | NLB + ACM cert |

## Step-by-Step Flow

```
1. Client → POST /transactions
   (Demo: via port-forward localhost:8000)
   (Prod:  via NLB → kong namespace)

2. Kong Gateway  [namespace: kong]
   ├─ OAuth / OIDC token validation  (Keycloak, namespace: security)
   ├─ Rate limiting per consumer
   ├─ Request schema validation
   ├─ PII redaction  (pre-function plugin)
   └─ Correlation ID injection  (x-correlation-id header)

3. Kong → Transactions Service  [namespace: fintech-services]
   └─ Network Policy: kong → fintech-services ALLOW

4. Transactions Service → Fraud API  [namespace: fraud-api]
   ├─ Internal mTLS  (cert from AWS Secrets Manager via External Secrets Operator)
   ├─ Sanitized payload only  (no raw PII)
   └─ Network Policy: fintech-services → fraud-api ALLOW only

5. Fraud API  [namespace: fraud-api]
   ├─ Rule-based checks  (fast-fail, < 5ms)
   ├─ Feature engineering
   ├─ LLM reasoning call  → Azure OpenAI  (external, HTTPS private endpoint)
   └─ Decision synthesis

6. Fraud API → Transactions Service
   └─ { decision: ALLOW | CHALLENGE | BLOCK, risk_score, reasons }

7. Transactions Service → Kong → Client
   └─ Kong post-function: strip internal headers before response reaches consumer
```
