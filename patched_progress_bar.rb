require 'progress_bar'

class PatchedProgressBar < ProgressBar

  def self.bar(*args, &block)
    bar = new(*args)
    yield(bar)
  ensure
    bar.finish
  end

  def finish
    write
    $stdout.puts
    $stdout.flush
  end

  def puts(text)
    clear!
    print(text)
    $stdout.puts
    write
  end

  def print(str)
    $stdout.write(str)
  end

  def write
    super
    $stdout.flush
  end

end

# Fix weird terminal sizes
$stdout.winsize = [$stdout.winsize.first, 200] if $stdout.winsize.last > 1000 rescue nil
