#!/usr/bin/env ruby

require 'rugged'
require 'json'
require_relative 'git_progress_bar'
require 'pathname'
require 'digest'
require 'io/console'

GitBase = 'https://github.com/USDA-NIFA/'
Repositories = ['bix_help#master', 'CAS#master', {'emailMQservice#docker-support' => 'emailservice'}, 'enterprise-search', 'jobmon', {'LMD' => 'lmd'}, 'lmd_bix', 'lmd_rails', 'nifa-docker-env', 'portal', {'REEport' => 'reeport'}]
CredentialsFile = __dir__ + '/git_credentials.json'

def git_credentials(credentials_file = CredentialsFile, username: nil, password: nil)

  md5 = Digest::MD5.hexdigest(credentials_file.to_s + username.to_s + password.to_s)
  if @last_md5 != md5
    @last_md5 = md5
    creds = begin
              JSON.parse(File.read(CredentialsFile), symbolize_names: true)
            rescue Errno::ENOENT => e
              {}
            rescue JSON::ParserError => e
              puts "Could not parse #{credentials_file}"
              puts e.message
              {}
            end

    creds[:username] = username.to_s if username
    creds[:password] = password.to_s if password


    unless creds[:username]
      print "Github Username: "
      $stdout.flush
      creds[:username] = $stdin.readline.chomp
    end

    unless creds[:password]
      # Note, attempting to use IO#noecho fails on some platforms
      print "Github Password: "
      $stdout.flush
      creds[:password] = $stdin.readline.chomp
    end

    @credentials = Rugged::Credentials::UserPassword.new(creds)
  end

  @credentials
end

def clone(repo, credentials = nil)

  credentials ||= git_credentials

  repo = Array(repo).flatten
  repo_name, branch = repo.first.split('#') + ['dev']
  destination = repo.size == 1 ? Pathname(repo_name) : Pathname(repo.last)

  if destination.exist? && !destination.directory?
    puts "Cannot clone #{repo_name}, the file #{destination.realpath} needs to be removed."
  else
    repository = nil
    if destination.exist? && !destination.empty?
      begin
        repository = Rugged::Repository.new(destination)
        puts "#{repo_name} already cloned."
        puts "  Currently on branch ##{repository.head.name.sub(/^refs\/heads\//, '')}"
      rescue Rugged::RepositoryError
        puts "Cannot clone #{repo_name}, the directory #{destination.realpath} is not empty and is not a repository."
      end
    else
      puts "Cloning #{repo_name}..."
      repository = GitProgressBar.clone_at(GitBase + repo_name, destination, credentials: credentials, branch: branch)
    end

    if repository
      # TODO: Set name and email as well
      puts "  Configuring core.autocrlf"
      repository.config['core.autocrlf'] = 'input'

      submodules = repository.submodules.each.to_a

      unless submodules.empty?
        puts "  Checking submodules..."
        submodules.each do |submodule|
          submodule.init if submodule.uninitialized?
          repository = submodule.repository rescue nil
          if repository
            puts "    #{submodule.name} already cloned."
          else
            puts "    Cloning #{submodule.name}..."
            Dir.chdir(destination.to_s) do |path|
              begin
                puts '  ' + submodule.url
                repository = GitProgressBar.clone_at(submodule.url.sub(/^git@github.com\:/, 'https://github.com/'), './' + submodule.path, credentials: credentials)
              rescue Rugged::CheckoutError, ArgumentError => e
                puts e.message
              end
            end
          end

          repository.config['core.autocrlf'] = 'input' if repository
        end
      end
    end

  end

end

def clone_repositories(credentials = nil, repositories: nil)
  puts "Cloning repositories."
  credentials ||= git_credentials
  repositories ||= Repositories
  repositories.each { |repository| clone(repository, credentials) }
end



if $PROGRAM_NAME == __FILE__
  if ARGV.empty?
    clone_repositories
  else
    # TODO: Switch to to_h
    clone_repositories(repositories: ARGV.map { |repo| repo.include?('=>') ? Hash[[repo.split('=>').map(&:strip)]] : repo  })
  end
end
