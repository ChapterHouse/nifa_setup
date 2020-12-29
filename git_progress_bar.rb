require_relative 'patched_progress_bar'

class GitProgressBar < PatchedProgressBar

  def self.clone_at(url, local_path, options = {})
    bar do |bar|
      options[:transfer_progress] = bar.method(:transfer_progress) if options[:transfer_progress] && !options[:transfer_progress].respond_to?(:call) || options[:transfer_progress].nil?
      repository = Rugged::Repository.clone_at(url, local_path.to_s, options)
      repository
    end
  end

  def initialize(*args)
    @max_set = args.first.is_a? Numeric
    super
  end

  def max=(new_max)
    @max_set = true
    super
  end

  def max_set?
    @max_set
  end

  def transfer_progress(total_objects, indexed_objects, received_objects, local_objects, total_deltas, indexed_deltas, received_bytes)
    self.max = total_objects unless max_set?
    self.count = (indexed_objects + received_objects) / 2
    now = ::Time.now
    if (now - @last_write) > 0.2 || @count >= max
      write
      @last_write = now
    end
  end

end