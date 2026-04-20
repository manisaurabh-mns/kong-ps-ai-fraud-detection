------+
                    |   Mobile Apps        |
                    +----------------------+
                               |
                    +----------------------+
                    |   Fintech Partners   |
                    +----------------------+
                               |
                    +----------------------+
                    | Internal Analytics   |
                    +----------------------+
                               |
                               v
                    +======================+
                    |      Kong Gateway    |
                    |----------------------|
                    | • OAuth / OIDC       |
                    | • mTLS               |
                    | • Rate Limiting      |
                    | • Schema Validation  |
                    | • PII Redaction      |
                    | • Observability      |
                    +======================+
                               |
          ------------------------------------------------
          |                                              |
          v                                              v
+------------------------+                   +------------------------+
|  Accounts Service      |                   | Transactions Service   |
| (accounts-service)    |                   | (transactions-service)|
+------------------------+                   +-----------+------------+
                                                            |
                                                            v
                                               +------------------------+
                                               |     Fraud API          |
                                               | (Internal Service)     |
                                               |------------------------|
                                               | • Feature extraction   |
                                               | • Rules engine         |
                                               | • AI reasoning         |
                                               | • Decision engine      |
                                               +-----------+------------+
                                                            |
                                                            v
                                               +------------------------+
                                               |   LLM Provider         |
                                               | (Azure OpenAI / GPT)   |
                                               |  – PRIVATE ACCESS –    |
                                               +------------------------+
