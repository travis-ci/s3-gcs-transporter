# s3-gcs-transporter
A small script to move things from S3 to GCS

It traverses an S3 bucket, and copies the content to GCS.
Since there is no direct pipe from S3 to GCS, it must download the files to the local machine first,
before uploading to GCS.

## Usage

```
$ ruby sync_script.rb \
  --s3-region=us-east-1 \
  --gcs-region=us-central1 \
  --gcs-creds-json=/path/to/gcs-creds.json \
  --gcs-project-id=your-gcp-project-id \
  --s3-bucket=your-s3-bucket-name \
  --s3-prefix=your/s3/prefix \
  --gcs-bucket=your-gcs-bucket-name \
  --gcs-prefix=your/gcs/prefix \
  --log-level=info
```
