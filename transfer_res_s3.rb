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
return_state = obj.upload_file(save_file)
puts return_state

s3.buckets.limit(50).each do |b|
  puts "#{b.name}"
end
