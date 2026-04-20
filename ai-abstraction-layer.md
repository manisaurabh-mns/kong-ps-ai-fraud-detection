+--------------------+
|   Business APIs    |
| (Accounts / Txns) |
+---------+----------+
          |
          v
+--------------------+
|     Kong           |
|--------------------|
| • Prompt control   |
| • Token limits     |
| • AI governance    |
+---------+----------+
          |
          v
+--------------------+
|   Fraud API        |
|--------------------|
| • Domain logic     |
| • Prompt templates |
| • Response filter  |
+---------+----------+
          |
          v
+--------------------+
|  LLM Model         |
| (Hidden)           |
+--------------------+
