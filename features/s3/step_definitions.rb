require 'openssl'

Before("@s3") do
  @client = Aws::S3::Client.new
  @created_buckets = []
end

After("@s3") do
  @created_buckets.each do |bucket|
    loop do
      objects = @client.list_object_versions(bucket: bucket).data.versions.map do |v|
        { key: v.key, version_id: v.version_id }
      end
      break if objects.empty?
      @client.delete_objects(bucket: bucket, delete: { objects: objects })
    end
    @client.delete_bucket(bucket: bucket)
  end
end

def create_bucket(options = {})
  @bucket_name = "aws-sdk-test-#{Time.now.to_i}-#{rand(1000)}"
  options[:bucket] = @bucket_name
  if @client.config.region != 'us-east-1' && !options[:create_bucket_configuration]
    options[:create_bucket_configuration] = {
      location_constraint: @client.config.region
    }
  end
  @client.create_bucket(options)
  @created_buckets << @bucket_name
end

When(/^I force path style requests$/) do
  @client = Aws.s3(force_path_style:true)
end

Given(/^I am using the S3 "(.*?)" region$/) do |region|
  @client = Aws.s3(region: region)
end

When(/^I create a bucket$/) do
  create_bucket
end

Given(/^I create a DNS compatible bucket$/) do
  create_bucket
end

When(/^I create a bucket with the location constraint "(.*?)"$/) do |loc|
  create_bucket(create_bucket_configuration: {
    location_constraint: loc
  })
end

Then(/^the bucket should have a location constraint of "(.*?)"$/) do |loc|
  resp = @client.get_bucket_location(bucket: @bucket_name)
  expect(resp.data.location_constraint).to eq(loc)
end

Then(/^the bucket should exist$/) do
  expect { @client.get_bucket_location(bucket: @bucket_name) }.not_to raise_error
end

When(/^I delete the bucket$/) do
  @client.delete_bucket(bucket: @bucket_name)
  @created_buckets.delete(@bucket_name)
end

Then(/^the bucket should not exist$/) do
  eventually(upto: 60) do
    begin
      @client.get_bucket_location(bucket: @bucket_name)
    rescue => @error
    end
    expect(@error).to be_kind_of(Aws::S3::Errors::NoSuchBucket)
  end
end

When(/^I put nothing to the key "(.*?)"$/) do |key|
  @client.put_object(bucket: @bucket_name, key: key)
end

When(/^I put "(.*?)" to the key "(.*?)"$/) do |data, key|
  @response = @client.put_object(bucket: @bucket_name, key: key, body: data)
end

When(/^I put the test png to the key "(.*?)"$/) do |key|
  file = File.open(File.join(File.dirname(__FILE__), 'test.png'), 'rb')
  @client.put_object(bucket: @bucket_name, key: key, body: file)
  file.close
end

Then(/^the object with the key "(.*?)" should have a content length of (\d+)$/) do |key, size|
  resp = @client.head_object(bucket: @bucket_name, key: key)
  expect(resp.data.content_length).to eq(size.to_i)
end

When(/^I page s3 objects prefixed "(.*?)" delimited "(.*?)" limit (\d+)$/) do |prefix, delimiter, max_keys|
  @responses = []
  @client.list_objects(
    bucket: @bucket_name,
    prefix: prefix,
    delimiter: delimiter,
    max_keys: max_keys
  ).each do |resp|
    @responses << resp
  end
end

Then(/^I should have received (\d+) responses$/) do |count|
  expect(@responses.size).to eq(count.to_i)
end

Given(/^I am using the S3 "(.*?)" endpoint$/) do |endpoint|
  @client = Aws.s3(endpoint: endpoint)
end

When(/^I create a bucket with a DNS compatible name that contains a dot$/) do
  @bucket_name = "aws.#{Time.now.to_i}.sdk"
  @client.create_bucket(bucket: @bucket_name)
end

Then(/^I should be able to delete the bucket$/) do
  @client.delete_bucket(bucket: @bucket_name)
end

Then(/^the bucket name should be in the request path$/) do
  endpoint = @response.context.http_request.endpoint
  expect(endpoint.path).to include(@bucket_name)
end

Then(/^the bucket name should not be in the request host$/) do
  endpoint = @response.context.http_request.endpoint
  expect(endpoint.host).not_to include(@bucket_name)
end

When(/^I put "(.*?)" to the key "(.*?)" with an aes key$/) do |body, key|
  @aes_key = OpenSSL::Cipher.new('aes-256-cbc').random_key
  @client.put_object(
    bucket: @bucket_name,
    key: key,
    body: body,
    sse_customer_algorithm: 'AES256',
    sse_customer_key: @aes_key)
end

Then(/^I can download the key "(.*?)" with the aes key$/) do |key|
  @client.get_object(
    bucket: @bucket_name,
    key: key,
    sse_customer_algorithm: 'AES256',
    sse_customer_key: @aes_key)
end

When(/^I get the object with the key "(.*?)"$/) do |key|
  @response = @client.get_object(bucket: @bucket_name, key: key)
end

Then(/^the body should be an IO object$/) do
  expect(@response.body).to be_kind_of(StringIO)
end

Then(/^the body\#read method should return "(.*?)"$/) do |str|
  expect(@response.body.read).to eq(str)
end

When(/^I put a large object with a broken content-md5$/) do
  begin
    @client.put_object(
      bucket: @bucket_name,
      key: 'key',
      body: '.' * 1024 * 1024,
      content_md5: 'abc')
  rescue => @error
  end
end

Then(/^I should receive an invalid digest error$/) do
  expect(@error).to be_kind_of(Aws::S3::Errors::InvalidDigest)
end

When(/^I put a large object$/) do
  @key = 'large-object'
  @client.put_object(bucket: @bucket_name, key: @key, body: '.' * 1024 * 1024)
end

Then(/^the object should exist$/) do
  @client.head_object(bucket: @bucket_name, key: @key)
end
