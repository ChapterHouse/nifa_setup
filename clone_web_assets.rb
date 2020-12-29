#!/usr/bin/env ruby

require 'pathname'
require 'net/http'
require_relative 'patched_progress_bar'
require 'time'

WebAssets = 'https://portal.nifa.usda.gov/web'

def hrefs_from(connection, path)

  html = connection.get(path, {'If-Modified-Since' => (Time.now + 100000).rfc2822}).read_body

  hrefs = html.scan(/<a  *href.*?>/)
  hrefs.map! { |a| /href\s*=\s*"([^"]*)"/.match(a) }
  hrefs.compact!
  hrefs.map! { |match| match.captures.first }
  hrefs.reject! { |href| ['?', '/', '#'].include?(href[0]) || href[0..3] == 'http' }

  # Too big for the moment
  hrefs.reject! { |href| href == 'crisprojectpages/' }

  hrefs.map! { |href| path + href }

  hrefs.partition { |href| href[-1] == '/' }
end

def locate_from(connection, base_path)

  return Marshal.load(File.binread('f.cache.txt')), Marshal.load(File.binread('d.cache.txt'))

  puts "Locating assets at #{base_path}"

  files = []
  directories = []

  stack = [base_path]

  PatchedProgressBar.bar(1) do |bar|

    until stack.empty?

      path = stack.shift
      bar.puts('  ' + path)

      new_directories, new_files = hrefs_from(connection, path)

      directories += new_directories
      files += new_files

      # Add the new directories to the stack for probing
      stack += new_directories

      # Sort breadth first
      stack.sort! do |a, b|
        rc = a.count('/') <=> b.count('/')
        rc != 0 ? rc : a <=> b
      end

      bar.max += new_directories.size
      bar.increment!
    end

  end

  # Remove url encoding
  files.map! { |file| URI.unescape(file) }
  directories.map! { |file| URI.unescape(file) }

  # Sort breadth first
  files.sort! do |a, b|
    rc = a.count('/') <=> b.count('/')
    rc != 0 ? rc : a <=> b
  end

  # Sort breadth first
  directories.sort! do |a, b|
    rc = a.count('/') <=> b.count('/')
    rc != 0 ? rc : a <=> b
  end

  File.binwrite('d.cache.txt', Marshal.dump(directories))
  File.binwrite('f.cache.txt', Marshal.dump(files))

  return files, directories

end

def remove_extra_web_items(web_directory, remote_files, remote_directories)

  existing_directories, existing_files = web_directory.glob("./**/*").partition(&:directory?)
  extras = (existing_files - remote_files) + (existing_directories - remote_directories)

  unless extras.empty?
    puts "Removing extra local files and directories previously downloaded..."
    PatchedProgressBar.bar(extras.size) do |bar|
      extras.each do |extra|
        bar.puts('  ' + extra.to_s)
        extra.delete
        bar.increment!
      end
    end
  end

end


def download_web_files(connection, web_directory, web_assets, files)

  # We don't need these gigs of pdfs
  files = files.reject { |file| File.dirname(file).include?('areera') && File.extname(file) == '.pdf' }

  # TODO: Check last modified or something to prevent downloading something we already have
  puts "Downloading web files..."
  PatchedProgressBar.bar(files.size) do |bar|
    files.each do |file|
      bar.puts('  ' + file.to_s)
      begin
        path = file
        body = connection.get(URI.escape(file), path.exist? ? {'If-Modified-Since' => path.mtime.rfc2822} : nil).body
        # puts "Write" if body
        # path.write(body) if body
      rescue Exception => e
        puts "Failed to download #{file}."
        puts e.message
      end
      bar.increment!
    end
  end

end

def clone_web_assets(web_assets = nil)

  web_directory = Pathname('web3')

  web_assets = URI(web_assets || WebAssets)
  web_assets.path += '/' unless web_assets.path[-1] == '/'

  Net::HTTP.start(web_assets.hostname, web_assets.port, :use_ssl => web_assets.scheme == 'https') do |connection|

    remote_files, directories = locate_from(connection, web_assets.path)

    # Convert to paths
    # You are here, turn into a hash again. Url => pathname
    files = remote_files.map  { |name| web_directory + name[web_assets.path.size..-1] }
    directories.map! { |directory| web_directory + directory[web_assets.path.size..-2] }

    # Pitch anything that was removed since last time we checked
    remove_extra_web_items(web_directory, files, directories)

    # Create the local directory structure under web
    directories.each(&:mkpath)

    # Download the files
    download_web_files(connection, web_directory, web_assets, remote_files)
  end

end

clone_web_assets(ARGV.first) if $PROGRAM_NAME == __FILE__
