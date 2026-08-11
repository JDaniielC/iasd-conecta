.PHONY: build deploy deploy-web clean

# GCP config
GCP_PROJECT := iasd-505120
GCS_BUCKET_SITE := gs://conecta-iasd-site
CDN_URL_MAP_SITE := conecta-iasd-site-url-map
REGION := us-east1

build:
	@echo "Building Flutter web..."
	flutter pub get
	flutter build web --release

deploy-web: build
	@echo "Uploading to Cloud Storage..."
	gsutil -m cp -r build/web/* $(GCS_BUCKET_SITE)/
	@echo "Invalidating CDN cache..."
	gcloud compute url-maps invalidate-cdn-cache $(CDN_URL_MAP_SITE) --path "/*" --project=$(GCP_PROJECT)
	@echo "✓ Deploy complete"
	@echo "Site available at: http://35.211.105.176"

clean:
	@echo "Cleaning build artifacts..."
	rm -rf build/

# Alias for CI (build only, no deploy)
build-ci: build
	@echo "✓ Build complete (ready for CI)"
