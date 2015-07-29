require 'set'

module Listen
  # TODO: refactor (turn it into a normal object, cache the stat, etc)
  class Directory
    def self.scan(snapshot, rel_path, options, recursive)
      record = snapshot.record

      _, previous = record.dir_entries(rel_path)

      dir = Pathname.new(record.root)
      path = dir + rel_path
      current = Set.new(path.children)

      Listen::Logger.debug do
        format('%s: %s(%s): %s -> %s',
               (options[:silence] ? 'Recording' : 'Scanning'),
               rel_path, options.inspect, previous.inspect, current.inspect)
      end

      record.update_dir(rel_path)

      current.each do |full_path|
        # Find old type so we can ensure we invalidate directory contents
        # if we were previously a file, and vice versa
        if previous.key?(full_path.basename)
          old = previous.delete(full_path.basename)
          old_type = old.key?(:mtime) ? :dir : :file
        else
          old_type = nil
        end

        item_rel_path = full_path.relative_path_from(dir).to_s
        if detect_type(full_path) == :dir
          if old_type == :file
            snapshot.invalidate(:file, item_rel_path, options)
          end

          # Only invalidate subdirectories if we're recursing or it is new
          if recursive || old_type.nil?
            snapshot.invalidate(:tree, item_rel_path, options)
          end
        else
          if old_type == :dir
            snapshot.invalidate(:tree, item_rel_path, options)
          end

          snapshot.invalidate(:file, item_rel_path, options)
        end
      end

      process_previous(snapshot, Pathname.new(rel_path), previous, options)
    rescue Errno::ENOENT, Errno::EHOSTDOWN
      record.unset_path(rel_path)
      process_previous(snapshot, Pathname.new(rel_path), previous, options)
    rescue Errno::ENOTDIR
      record.unset_path(rel_path)
      process_previous(snapshot, path, previous, options)
      snapshot.invalidate(:file, rel_path, options)
    rescue
      Listen::Logger.warn do
        format('scan DIED: %s:%s', $ERROR_INFO, $ERROR_POSITION * "\n")
      end
      raise
    end

    def self.process_previous(snapshot, path, previous, options)
      previous.each do |entry, data|
        type = data.key?(:mtime) ? :file : :tree
        rel_path_s = (path + entry).to_s
        snapshot.invalidate(type, rel_path_s, options)
      end
    end

    def self.detect_type(full_path)
      stat = ::File.lstat(full_path.to_s)
      stat.directory? ? :dir : :file
    rescue Errno::ENOENT
      # report as dir for scanning
      :dir
    end
  end
end
