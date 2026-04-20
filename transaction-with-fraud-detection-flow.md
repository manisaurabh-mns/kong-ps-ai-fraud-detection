1 /transactions
2. Kong Gateway
   ├─ OAuth token validation
   ├─ Rate limiting per consumer
   ├─ Schema validation
   ├─ PII redaction
   └─ Correlation ID injection

3. Kong → Transactions Service
4. Transactions Service → Fraud API
   ├─ Internal mTLS
   ├─ Sanitized payload only

5. Fraud API
   ├─ Rule-based checks (fast fail)
   ├─ Feature engineering
   ├─ LLM reasoning call
   └─ Decision synthesis

6. Fraud API → Transactions Service
   └─ ALLOW / CHALLENGE / BLOCK

7. Transactions Service → Kong → Client
