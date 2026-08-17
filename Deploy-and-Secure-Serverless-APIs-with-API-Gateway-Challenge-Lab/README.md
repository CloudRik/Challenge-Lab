## ARC109 Lab Automation

Automates the three tasks in the Google Skills lab “Deploy and Secure Serverless APIs with API Gateway”.

Run in Cloud Shell


curl -fsSL https://raw.githubusercontent.com/YOUR-USERNAME/YOUR-REPO/main/solve.sh | bash


The script detects the active Google Cloud project automatically. If no project is configured, it asks for the Project ID. It derives the Project Number and other runtime values automatically.

What it automates

Deploys gcfunction as a 2nd-gen Node.js 22 HTTP function in us-east1.

Creates API gcfunction-api, config gcfunction-api, and gateway gcfunction-api.

Creates Pub/Sub topic demo-topic and the deterministic default subscription demo-topic-sub.

Redeploys the function so the backend publishes Hello from Cloud Run functions! to the topic.

Invokes the endpoint through API Gateway and shows a success banner.

Notes

The lab uses fixed resource names and region, while the Google Cloud Project ID and Project Number vary per lab session. The script derives those values instead of hard-coding them.

For production sharing, pin the raw script to a reviewed Git commit/tag rather than an unchanging main branch.
