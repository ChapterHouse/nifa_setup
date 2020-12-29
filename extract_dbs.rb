#!/usr/bin/env ruby

require 'pathname'
require 'date'
require 'bzip2/ffi'
require 'rubygems/package'
require_relative 'patched_progress_bar'

def database_archives
  Dir.chdir('./nifa-docker-env/data/mysql/dev-dbs') do
    Pathname.glob('sample-dbs-mysql*.tar.bz2').map do |file|
      match = /.*?(\d+)\..*/.match(file.basename.to_s)
      if match
        begin
          [DateTime.strptime(match[1].to_s, "%Y%m%d%H%M"), file]
        rescue ArgumentError
          nil
        end
      end
    end.compact.sort { |a, b| b.first <=> a.first }.to_h
  end
end

# TODO: Interact directly with google drive to get the files
# https://flaviocopes.com/google-api-authentication/
def download_dbs
  Dir.chdir('./nifa-docker-env/data/mysql/dev-dbs') do
    puts "Please download the database dump from https://drive.google.com/drive/folders/1xF8YdBb9MtKw2zeOnnF3DUHY4cP5PhXk"
    puts "and place it in #{Pathname('.').realpath}"
    puts "Press return when ready to continue..."
    gets
  end
end

def extract_dbs(date_time=nil)
  puts "Extracting databases..."

  archives = database_archives

  while archives.empty?
    puts "No data archives found."
    download_dbs
    archives = database_archives
  end

  Dir.chdir('./nifa-docker-env/data/mysql/dev-dbs') do

    date_time ||= archives.first.first
    date_time = DateTime.strptime(date_time.to_s, "%Y%m%d%H%M") rescue date_time unless date_time.is_a?(DateTime)

    archive = archives[date_time]
    if archive

      puts "Using data archived at #{date_time.strftime('%-l:%M %P on %A, %B %-d, %Y')}"

      tar_data = StringIO.new('')
      tar_data.binmode

      estimated_size = archive.size * 6.75 # 6.75 is just an approximate figure I estimated by observation.
      read_size = 1024 * 1024 * 16

      puts "Decompressing #{archive}..."
      PatchedProgressBar.bar(estimated_size) do |bar|
        Bzip2::FFI::Reader.open(archive.to_s, small: false) do |bzip|
          data = bzip.read(read_size)
          while data
            tar_data.write(data)
            bar.increment!(data.size)
            data = bzip.read(read_size)
          end
        end
        bar.increment!(bar.max - bar.count) if bar.count < bar.max
      end

      tar_data.rewind

      Gem::Package::TarReader.new(tar_data) do |tar|
        puts "Extracting..."
        tar.each do |tar_entry|
          if tar_entry.file?
            file = Pathname(tar_entry.full_name).basename
            puts "  #{file}"
            file.binwrite(tar_entry.read)
          end
        end
      end

    else
      date_time = date_time.strftime("%Y%m%d%H%M") if date_time.respond_to?(:strftime)
      puts "Could not find archive for #{date_time}"
    end

  end

end


extract_dbs(ARGV.first) if $PROGRAM_NAME == __FILE__