#!/usr/bin/env ruby

puts "Before: #{$LOAD_PATH}"
curr_dir = Dir.pwd
puts curr_dir
gem_loc = curr_dir + '/vendor/bundle/ruby/2.2.0/gems/'
puts gem_loc
gem_dirs = Dir.entries(gem_loc).select {|entry| File.directory? File.join(gem_loc,entry) and !(entry =='.' || entry == '..') }
puts gem_dirs
gem_dirs.each do |gem_dir|
  lib = gem_loc + gem_dir + '/lib'
  $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
  puts lib
end
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
