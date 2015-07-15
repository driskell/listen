require 'set'

module Listen
  # TODO: refactor (turn it into a normal object, cache the stat, etc)
  class Directory
    def self.scan(snapshot, rel_path, options)
      record = snapshot.record
      dir = Pathname.new(record.root)
      existed, previous = record.dir_entries(dir, rel_path)

      if options[:recursive]
        # Recursion is forced (not automatic), keep recursing
        opts = options
      elsif !options[:is_recursing]
        # We're top level - automatically recurse into subfolder to check if
        # they are new
        opts = options.dup
        opts[:is_recursing] = true
      elsif existed
        # We're one level into automatic recursion and the subfolder is known
        # and is not new, stop recursing
        _log(:debug) do
          format('Directory unchanged: %s(%s)', rel_path, options.inspect)
        end
        return
      else
        # New subfolder, keep recursing
        opts = options
      end

      # TODO: use children(with_directory: false)
      path = dir + rel_path
      current = Set.new(path.children)

      Listen::Logger.debug do
        format('%s: %s(%s): %s -> %s',
               (options[:silence] ? 'Recording' : 'Scanning'),
               rel_path, options.inspect, previous.inspect, current.inspect)
      end

      current.each do |full_path|
        type = detect_type(full_path)
        item_rel_path = full_path.relative_path_from(dir).to_s
        _change(snapshot, type, item_rel_path, opts)
      end

      # TODO: this is not tested properly
      previous = previous.reject { |entry, _| current.include? path + entry }

      _async_changes(snapshot, Pathname.new(rel_path), previous, opts)

    rescue Errno::ENOENT, Errno::EHOSTDOWN
      record.unset_path(rel_path)
      _async_changes(snapshot, Pathname.new(rel_path), previous, opts)

    rescue Errno::ENOTDIR
      # TODO: path not tested
      record.unset_path(rel_path)
      _async_changes(snapshot, path, previous, opts)
      _change(snapshot, :file, rel_path, opts)
    rescue
      Listen::Logger.warn do
        format('scan DIED: %s:%s', $ERROR_INFO, $ERROR_POSITION * "\n")
      end
      raise
    end

    def self._async_changes(snapshot, path, previous, options)
      fail "Not a Pathname: #{path.inspect}" unless path.respond_to?(:children)
      # Always recurse removed entries
      opts = options.dup
      opts[:recursive] = true

      previous.each do |entry, data|
        # TODO: this is a hack with insufficient testing
        type = data.key?(:mtime) ? :file : :dir
        rel_path_s = (path + entry).to_s
        _change(snapshot, type, rel_path_s, opts)
      end
    end

    def self._change(snapshot, type, path, options)
      return snapshot.invalidate(type, path, options) if type == :dir

      snapshot.invalidate(type, path, opts)
    end

    def self.detect_type(full_path)
      # TODO: should probably check record first
      stat = ::File.lstat(full_path.to_s)
      stat.directory? ? :dir : :file
    rescue Errno::ENOENT
      # TODO: ok, it should really check the record here
      # report as dir for scanning
      :dir
    end
  end
end
