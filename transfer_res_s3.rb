#!/usr/bin/env ruby

gem_loc = '/usr/local/lib/ruby/gems/2.2.0/gems/'
gem_dirs = Dir.entries(gem_loc).select {|entry| File.directory? File.join(gem_loc,entry) and !(entry =='.' || entry == '..') }
gem_dirs.sort.each do |gem_dir|
  lib_loc = ''
  lib_loc = gem_loc + gem_dir + '/lib'
  $LOAD_PATH.unshift(lib_loc) unless $LOAD_PATH.include?(lib_loc)
end 

require 'bundler'
require 'securerandom'
require 'aws-sdk-s3'
require 'json'

region = 'us-east-1'

ida = SecureRandom.uuid
idb = SecureRandom.uuid
outfilenamea = ida.to_s + '.txt'
file = File.open(outfilenamea, 'w')
file.puts "AWS transfer test file.  Did it work? " + outfilenamea
file.close

outfilenameb = idb.to_s + '.txt'
IO.copy_stream(outfilenamea, outfilenameb)

s3 = Aws::S3::Resource.new(region: region)

save_file = './' + outfilenamea
bucket_name = 'btapresultsbucket'
name = File.basename(save_file) + "test"

obj = s3.bucket(bucket_name).object(name)
return_state = obj.upload_file(save_file)
puts return_state

file_id = "test" + outfilenameb
save_fileb = './' + outfilenameb
s3.put_object(bucket: bucket_name, key: file_id, body: outfilenameb)
s3.buckets.limit(50).each do |b|
  puts "#{b.name}"
end

