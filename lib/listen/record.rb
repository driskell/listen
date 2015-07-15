require 'listen/record/entry'
require 'listen/record/symlink_detector'

module Listen
  class Record
    # TODO: one Record object per watched directory?
    # TODO: deprecate

    attr_reader :root
    def initialize(directory)
      @tree = _auto_hash
      @tree['.'] = _auto_hash
      @root = directory.to_s
    end

    def update_dir(rel_path)
      dirname, basename = Pathname(rel_path).split.map(&:to_s)
      _fast_update_dir(rel_path, dirname, basename)
    end

    def update_file(rel_path, data)
      dirname, basename = Pathname(rel_path).split.map(&:to_s)
      _fast_update_file(dirname, basename, data)
    end

    def unset_path(rel_path)
      dirname, basename = Pathname(rel_path).split.map(&:to_s)
      _fast_unset_path(dirname, basename)
    end

    def file_data(rel_path)
      dirname, basename = Pathname(rel_path).split.map(&:to_s)
      tree[dirname] ||= {}
      tree[dirname][basename] ||= {}
      tree[dirname][basename].dup
    end

    def dir_entries(rel_path)
      rel_path = rel_path.to_s
      [tree.key?(rel_path), tree[rel_path] ||= _auto_hash]
    end

    def build
      @tree = _auto_hash
      # TODO: test with a file name given
      # TODO: test other permissions
      # TODO: test with mixed encoding
      symlink_detector = SymlinkDetector.new
      remaining = Queue.new
      remaining << Entry.new(root, '.', '.')
      _fast_build_dir(remaining, symlink_detector) until remaining.empty?
    end

    private

    def _auto_hash
      Hash.new { |h, k| h[k] = Hash.new }
    end

    def tree
      @tree
    end

    def _fast_update_dir(record_as_key, dirname, basename)
      tree[record_as_key] ||= {}
      tree[dirname] ||= {}
      tree[dirname].merge!(basename => {}) if basename != '.'
    end

    def _fast_update_file(dirname, basename, data)
      tree[dirname] ||= {}
      tree[dirname][basename] = (tree[dirname][basename] || {}).merge(data)
    end

    def _fast_unset_path(dirname, basename)
      # this may need to be reworked to properly remove
      # entries from a tree, without adding non-existing dirs to the record
      return unless tree.key?(dirname)
      tree[dirname].delete(basename)
    end

    def _fast_build_dir(remaining, symlink_detector)
      entry = remaining.pop
      children = entry.children # NOTE: children() implicitly tests if dir
      symlink_detector.verify_unwatched!(entry)
      children.each { |child| remaining << child }
      _fast_update_dir(entry.record_as_key, entry.relative, entry.name)
    rescue Errno::ENOTDIR
      _fast_try_file(entry)
    rescue SystemCallError, SymlinkDetector::Error
      _fast_unset_path(entry.relative, entry.name)
    end

    def _fast_try_file(entry)
      _fast_update_file(entry.relative, entry.name, entry.meta)
    rescue SystemCallError
      _fast_unset_path(entry.relative, entry.name)
    end
  end
end
