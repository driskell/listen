require 'set'

module Listen
  class Directory
    def self.scan(queue, sync_record, dir, rel_path, options)
      return unless (record = sync_record.async)

      # dir_entries implicitly creates new nodes when required
      previous, existed = sync_record.dir_entries(dir, rel_path)

      # Always recurse the directory one level
      # Only allow recursion deeper if the directory is new or removed
      opts = options.dup
      opts[:is_recursing] = true
      return if options[:is_recursing] && !options[:recursive] && existed

      # TODO: use children(with_directory: false)
      path = dir + rel_path
      current = Set.new(path.children)

      _log(:debug) do
        format('%s: %s(%s): %s -> %s',
               (options[:silence] ? 'Recording' : 'Scanning'),
               rel_path, options.inspect, previous.inspect, current.inspect)
      end

      current.each do |full_path|
        type = full_path.directory? ? :dir : :file
        item_rel_path = full_path.relative_path_from(dir).to_s
        _change(queue, type, dir, item_rel_path, opts)
      end

      # TODO: this is not tested properly
      previous.reject! { |entry, _| current.include? path + entry }

      _async_changes(dir, rel_path, queue, previous, opts)

    rescue Errno::ENOENT
      record.unset_path(dir, rel_path)
      _async_changes(dir, rel_path, queue, previous, opts)

    rescue Errno::ENOTDIR
      # TODO: path not tested
      record.unset_path(dir, rel_path)
      _async_changes(dir, path, queue, previous, opts)
      _change(queue, :file, dir, rel_path, opts)
    rescue
      _log(:warn) do
        format('scan DIED: %s:%s', $ERROR_INFO, $ERROR_POSITION * "\n")
      end
      raise
    end

    def self._async_changes(dir, path, queue, previous, options)
      # Always recurse removed entries
      opts = options.dup
      opts[:recursive] = true

      previous.each do |entry, data|
        # TODO: this is a hack with insufficient testing
        type = data.key?(:mtime) ? :file : :dir
        _change(queue, type, dir, (Pathname(path) + entry).to_s, opts)
      end
    end

    def self._change(queue, type, dir, path, options)
      return queue.change(type, dir, path, options) if type == :dir

      # Minor param cleanup for tests
      # TODO: use a dedicated Event class
      opts = options.dup
      opts.delete(:is_recursing)
      opts.delete(:recursive)
      if opts.empty?
        queue.change(type, dir, path)
      else
        queue.change(type, dir, path, opts)
      end
    end

    def self._log(type, &block)
      return unless Celluloid.logger
      Celluloid.logger.send(type) do
        block.call
      end
    end
  end
end
