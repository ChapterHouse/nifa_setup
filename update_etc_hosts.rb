#!/usr/bin/env ruby

def hosts_file
  Gem.win_platform? ? 'c:/windows/system32/drivers/etc/hosts' : '/etc/hosts'
end

def etc_hosts_set?
  File.readlines(hosts_file).map { |line| line.strip.gsub(/  */, ' ').split(' ') }.select { |x| x.size == 2 && x.first == '127.0.0.1' && x.last == 'nifa.docker.env' }.size > 0
end

def update_etc_hosts
  puts "Examining hosts file..."
  unless etc_hosts_set?
    puts "Updating #{hosts_file} to allow a connection locally with the reverse proxy at the nifa.docker.env domain."
    begin
      File.open(hosts_file, 'a') do |hosts|
        hosts.puts "# Allow a connection locally with the reverse proxy at the nifa.docker.env domain"
        hosts.puts "127.0.0.1 nifa.docker.env"
      end
    rescue Errno::EACCES
      puts "Permission denied attempting to update #{hosts_file}"
      puts "Please rerun this setup as #{Gem.win_platform? ? 'Administrator' : 'root'} or an account with permissions to edit the hosts file."
      puts "Alternatively, manually add '127.0.0.1 nifa.docker.env' to the bottom of #{hosts_file}"
    end
  else
    puts "Hosts file currently has the correct entry for nifa.docker.env."
  end
end

update_etc_hosts if $PROGRAM_NAME == __FILE__