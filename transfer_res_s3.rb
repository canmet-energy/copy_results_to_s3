require 'aws-sdk-s3'  # v2: require 'aws-sdk'
region = 'us-east-1'

s3 = Aws::S3::Resource.new(region: region)

file = File.open('test_out.txt', 'w')
file.puts "AWS transfer test file.  Did it work?"
file.close

save_file = './test_out.txt'
bucket = 'btapresultsbucket'
name = File.basename(save_file)

obj = s3.bucket(bucket).object(name)
obj.upload_file(save_file)

s3.buckets.limit(50).each do |b|
  puts "#{b.name}"
end