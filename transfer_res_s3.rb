#!/usr/bin/env ruby

puts "Before: #{$LOAD_PATH}"
lib = '/usr/local/lib/ruby/gems/2.2.0/gems/aws-sdk-s3-1.44.0/lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
lib = '/usr/local/lib/ruby/gems/2.2.0/gems//aws-sdk-core-3.58.0/lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
lib = '/usr/local/lib/ruby/gems/2.2.0/gems/aws-sigv4-1.1.0/lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
puts "After: #{$LOAD_PATH}" 

require 'bundler'
require 'securerandom'
require 'aws-sdk-s3'
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
if obj.upload_file(save_file).nil?
  puts "Upload worked!"
  puts outfilename
else
  puts "Boooooooooooooooooooo!"
end

s3.buckets.limit(50).each do |b|
  puts "#{b.name}"
end
