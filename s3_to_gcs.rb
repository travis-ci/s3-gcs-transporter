#!/usr/bin/env ruby

require 'aws-sdk'
require 'google/cloud/storage'
#require 'smarter_csv'
require 'optparse'
require 'pathname'
require 'fileutils'
require 'logger'
require 'rainbow'

ALWAYS_UPDATE = /(head|dev|snapshot|nightly)|\bphp-\d+\.\d+\.tar/

def logger
  @logger ||= Logger.new(
    $stderr,
    level: Logger::WARN,
    formatter: proc do |severity, time, progname, msg|
      case severity
      when "UNKOWN", "FATAL", "ERROR"
        c = :red
      when /WARN/
        c = :yellow
      when /INFO/
        c = :blue
      when /DEBUG/
        c = :default
      end
      Logger::Formatter::Format % [severity[0..0], time.strftime(@datetime_format || "%Y-%m-%dT%H:%M:%S.%6N "), $$, Rainbow(severity).color(c), progname, msg]
    end
  )
end

def options
  @options
end

@options = {
  s3_region: 'us-east-1',
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end

  opts.on("--s3-region=MANDATORY", "S3 region") do |s3_region|
    options[:s3_region] = s3_region
  end

  opts.on("--gcs-region=MANDATORY", "GCS region") do |gcs_region|
    options[:gcs_region] = gcs_region
  end

  opts.on("--gcs-creds-json=MANDATORY", "JSON file containing GCS credentials, as downloaded from GCP") do |json_file|
    options[:gcs_creds_json] = json_file
  end

  opts.on("--gcs-project-id=MANDATORY", "GCS project ID") do |proj_id|
    options[:gcs_project_id] = proj_id
  end

  opts.on("--s3-bucket=MANDATORY", "Bucket to copy from (on S3)") do |bucket|
    options[:s3_bucket] = bucket
  end

  opts.on("--s3-prefix=MANDATORY", "Bucket prefix for S3") do |prefix|
    options[:s3_prefix] = prefix
  end

  opts.on("--gcs-bucket=MANDATORY", "Bucket to copy to (on GCS)") do |bucket|
    options[:gcs_bucket] = bucket
  end

  opts.on("--gcs-prefix=MANDATORY", "Bucket prefix for GCS") do |prefix|
    options[:gcs_prefix] = prefix
  end

  opts.on("--log-level=MANDATORY", "Log level") do |level|
    options[:log_level] = level
  end
end

parser.parse!

logger.level = options[:log_level] if options[:log_level]
logger.level = Logger::DEBUG if options[:verbose]
Google::Apis.logger = logger

logger.debug options.inspect

def s3
  @s3 ||= Aws::S3::Resource.new(
    region: options[:s3_region] || 'us-east-1'
  )
end

def gcs
  @gcs ||= Google::Cloud::Storage.new(
    project_id: options[:gcs_project_id],
    credentials: options[:gcs_creds_json]
  )
end

def main
  s3_bucket  = s3.bucket(options[:s3_bucket])
  gcs_bucket = gcs.bucket(options[:gcs_bucket])

  s3_bucket.objects.each do |obj_summary|
    obj_key = obj_summary.key
    unless obj_summary.size > 0
      logger.info "Skipping blank file #{obj_key}"
      next
    end
    unless obj_key.start_with?(options[:s3_prefix])
      logger.info "Skipping #{obj_key} because it does not match prefix #{options[:s3_prefix]}"
      next
    end

    pn = Pathname.new(obj_key)
    gcs_obj_key = obj_key.sub(options[:s3_prefix], options[:gcs_prefix])

    if obj_key.end_with?(".sha256sum.txt.sha256sum.txt")
      logger.info "Removing #{obj_key}"
      obj_summary.delete
      gcs_bucket.file(gcs_obj_key).delete
      next
    end

    checksums_match_p = false

    begin
      checksum_obj_key = obj_key
      gcs_checksum_obj_key = gcs_obj_key

      if !obj_key.end_with?(".sha256sum.txt")
        checksum_obj_key = obj_key + ".sha256sum.txt"
        gcs_checksum_obj_key = gcs_obj_key + ".sha256sum.txt"
      end

      s3_obj_checksum = s3.client.get_object(
        bucket: s3_bucket.name,
        key: checksum_obj_key
      ).body.string
      gcs_obj_checksum = (gcs_obj_checksum_obj = gcs_bucket.find_file(gcs_checksum_obj_key)) && gcs_obj_checksum_obj.download.string

      if checksums_match_p = (s3_obj_checksum == gcs_obj_checksum)
        logger.info "Skipping #{obj_key} because checksums match"
      end
    rescue Aws::S3::Errors::ServiceError => s3err
      logger.warn(obj_key + " " + s3err.message)
    rescue Google::Cloud::Error => gcerr
      logger.warn(obj_key + " " + gcerr.message)
    end

    next if checksums_match_p

    logger.info "Processing #{obj_key}"
    logger.info "Downloading #{obj_key}"

    local_file = File.basename(pn)

    if !File.exist?(local_file)
      unless obj_summary.download_file(local_file)
        logger.warn "Failed to download #{obj_key}"
        next
      end
      # generate and upload sha256sum file
      if !local_file.end_with?(".sha256sum.txt")
        begin
          s3.client.get_object(bucket: s3_bucket.name, key: obj_key + ".sha256sum.txt")
        rescue Aws::S3::Errors::NoSuchKey => no_such_key
          logger.warn(obj_key + ".sha256sum.txt does not exist")
        end
        `sha256sum #{local_file} > #{local_file}.sha256sum.txt`
        logger.debug "Generated sha256 checksum file: #{File.read(local_file + ".sha256sum.txt")}"
        logger.info "Uploading #{local_file + ".sha256sum.txt"} to S3"
        s3_bucket.put_object(
          acl: "public-read",
          body: File.read(local_file + ".sha256sum.txt"),
          key: obj_key + ".sha256sum.txt"
        )
        logger.info "Uploading #{local_file + ".sha256sum.txt"} to GCS"
        gcs_bucket.create_file(local_file + ".sha256sum.txt", gcs_obj_key + ".sha256sum.txt")
      end
    end
    logger.info "Downloaded #{obj_key}"

    # Upload to GCS
    logger.debug "local_file: #{local_file}"
    logger.debug "gcs_obj_key: #{gcs_obj_key}"
    logger.info "Uploading #{gcs_obj_key}"
    if gcs_bucket.create_file(local_file, gcs_obj_key)
      logger.info "Uploaded #{gcs_obj_key}"
      FileUtils.rm_f(local_file)
    end
  end
end

main
