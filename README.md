# fruit_basket_app

A new Flutter project.

## Deploy Web To Cloud Run

1. Install and authenticate Google Cloud CLI:
   - `gcloud auth login`
   - `gcloud config set project fruit-basket-ab8fd`

2. Enable required APIs (first time only):
   - `gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com`

3. Build and deploy from project root:
   - `gcloud run deploy fruit-basket-web --source . --region asia-south1 --allow-unauthenticated`

4. Open the service URL shown in terminal.
