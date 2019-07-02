#!/usr/bin/env ruby
require 'bundler'
require 'securerandom'
require '/var/oscli/gems/ruby/2.2.0/gems/aws-sdk-s3'
region = 'us-east-1'

id = SecureRandom.uuid
outfilename = id.to_s + '.txt'
file = File.open(outfilename, 'w')
file.puts "AWS transfer test file.  Did it work? " + outfilename
file.close

s3 = Aws::S3::Resource.new(region: region)

save_file = './' + outfilename
bucket = 'btapresultsbucket'
name = File.basename(save_file)

obj = s3.bucket(bucket).object(name)
obj.upload_file(save_file)

s3.buckets.limit(50).each do |b|
  puts "#{b.name}"
end