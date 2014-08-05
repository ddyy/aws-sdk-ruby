Before("@sqs") do
  @client = Aws::SQS::Client.new
  @sqs_created_queues = []
end

After("@sqs") do
  @sqs_created_queues.each do |url|
    @client.delete_delete_queue(queue_url: url)
  end
end

Given(/^I create a queue in "(.*?)"$/) do |region|
  name = "aws-sdk-core-integration-test-#{Time.now.to_i}-#{rand(1000)}"
  resp = Aws::SQS::Client.new(region: region).create_queue(queue_name: name)
  @queue_url = resp.queue_url
end

When(/^I operate on that queue in "(.*?)"$/) do |region|
  @response = Aws::SQS::Client.new(region: region).send_message(
    queue_url: @queue_url,
    message_body: 'hello'
  )
end

Then(/^the request should be made against "(.*?)"$/) do |region|
  expect(@response.context.http_request.endpoint.to_s).to include(region)
end


