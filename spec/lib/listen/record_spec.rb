RSpec.describe Listen::Record do
  let(:dir) { instance_double(Pathname, to_s: '/dir') }
  let(:record) { Listen::Record.new(dir) }

  before do
    allow(::File).to receive(:symlink?).with('/dir').and_return(false)
  end

  def dir_entries_for(hash)
    hash.each do |dir, entries|
      allow(::Dir).to receive(:entries).with(dir) { entries }
    end
  end

  def real_directory(hash)
    dir_entries_for(hash)
    hash.each do |dir, _|
      realpath(dir)
    end
  end

  def file(path)
    allow(::Dir).to receive(:entries).with(path).and_raise(Errno::ENOTDIR)
    realpath(path)
  end

  def lstat(path, stat = nil)
    stat ||= instance_double(::File::Stat, mtime: 2.3, mode: 0755)
    allow(::File).to receive(:lstat).with(path).and_return(stat)
    stat
  end

  def realpath(path)
    allow(::File).to receive(:realpath).with(path).and_return(path)
    allow(::File).to receive(:symlink?).with(path).and_return(false)
    path
  end

  def symlink(src, dst)
    allow(::File).to receive(:realpath).with(src).and_return(dst)
    allow(::File).to receive(:symlink?).with(src).and_return(true)
    src
  end

  def record_tree(record)
    record.instance_variable_get(:@tree)
  end

  describe '#update_file' do
    context 'with path in watched dir' do
      it 'sets path by spliting dirname and basename' do
        expect(record.update_file('file.rb', mtime: 1.1)).to eq false
        entries = record_tree(record)['.']
        expect(entries).to eq('file.rb' => { mtime: 1.1 })
      end

      it 'sets path and keeps old data not overwritten' do
        expect(record.update_file('file.rb', foo: 1, bar: 2)).to eq false
        expect(record.update_file('file.rb', foo: 3)).to eq true
        entries = record_tree(record)['.']
        expect(entries['file.rb']).to eq(foo: 3, bar: 2)
      end
    end

    context 'with subdir path' do
      before { record.update_dir('path') }

      it 'sets path by spliting dirname and basename' do
        expect(record.update_file('path/file.rb', mtime: 1.1)).to eq false
        entries = record_tree(record)['path']
        expect(entries).to eq('file.rb' => { mtime: 1.1 })
      end

      it 'sets path and keeps old data not overwritten' do
        expect(record.update_file('path/file.rb', foo: 1, bar: 2)).to eq false
        expect(record.update_file('path/file.rb', foo: 3)).to eq true
        entries = record_tree(record)['path']
        expect(entries['file.rb']).to eq(foo: 3, bar: 2)
      end
    end
  end

  describe '#update_dir' do
    it 'correctly sets new directory data' do
      expect(record.update_dir('path')).to eq false
      expect(record.update_dir('path/subdir')).to eq false
      expect(record_tree(record)).to eq(
        '.' => { 'path' => {} },
        'path' => { 'subdir' => {} },
        'path/subdir' => {},
      )
    end

    it 'sets path and keeps old data not overwritten' do
      record.update_dir('path')
      expect(record.update_dir('path/subdir')).to eq false
      record.update_file('path/subdir/file.rb', mtime: 1.1)
      expect(record.update_dir('path/subdir')).to eq true
      record.update_file('path/subdir/file2.rb', mtime: 1.2)
      expect(record.update_dir('path/subdir')).to eq true

      expect(record_tree(record)).to eq(
        '.' => { 'path' => {} },
        'path' => { 'subdir' => {} },
        'path/subdir' => {
          'file.rb' => { mtime: 1.1 },
          'file2.rb' => { mtime: 1.2 },
        },
      )
    end
  end

  describe '#unset_path' do
    context 'within watched dir' do
      context 'when path is present' do
        before { record.update_file('file.rb', mtime: 1.1) }

        it 'unsets path' do
          record.unset_path('file.rb')
          expect(record_tree(record)).to eq('.' => {})
        end
      end

      context 'when path not present' do
        it 'unsets path' do
          record.unset_path('file.rb')
          expect(record_tree(record)).to eq('.' => {})
        end
      end
    end

    context 'within subdir' do
      context 'when path is present' do
        before do
          record.update_dir('path')
          record.update_file('path/file.rb', mtime: 1.1)
        end

        it 'unsets path' do
          record.unset_path('path/file.rb')
          expect(record_tree(record)).to eq(
            '.' => { 'path' => {} },
            'path' => {},
          )
        end
      end

      context 'when path not present' do
        it 'unsets path' do
          record.unset_path('path/file.rb')
          expect(record_tree(record)).to eq('.' => {})
        end
      end
    end

    context 'with directory path' do
      before do
        record.update_dir('path')
        record.update_file('path/file.rb', mtime: 1.1)
      end

      it 'unsets path and dir entries' do
        record.unset_path('path/file.rb')
        record.unset_path('path')
        expect(record_tree(record)).to eq('.' => {})
      end
    end
  end

  describe '#file_data' do
    context 'with path in watched dir' do
      context 'when path is present' do
        before { record.update_file('file.rb', mtime: 1.1) }

        it 'returns file data' do
          expect(record.file_data('file.rb')).to eq(mtime: 1.1)
        end
      end

      context 'path not present' do
        it 'return empty hash' do
          expect(record.file_data('file.rb')).to be_empty
        end
      end
    end

    context 'with path in subdir' do
      context 'when path is present' do
        before { record.update_file('path/file.rb', mtime: 1.1) }

        it 'returns file data' do
          expected = { mtime: 1.1 }
          expect(record.file_data('path/file.rb')).to eq expected
        end
      end

      context 'path not present' do
        it 'return empty hash' do
          expect(record.file_data('path/file.rb')).to be_empty
        end
      end
    end
  end

  describe '#dir_entries' do
    context 'in watched dir' do
      subject { record.dir_entries('.') }

      context 'with no entries' do
        it 'returns that it is an empty directory' do
          should eq({})
        end
      end

      context 'with file.rb in record' do
        before { record.update_file('file.rb', mtime: 1.1) }
        it 'returns that it contains a file' do
          should eq('file.rb' => { mtime: 1.1 })
        end
      end

      context 'with subdir/file.rb in record' do
        before do
          record.update_dir('subdir')
          record.update_file('subdir/file.rb', mtime: 1.1)
        end

        it 'returns that it contains a directory' do
          should eq('subdir' => {})
        end
      end
    end

    context 'in subdir /path' do
      subject { record.dir_entries('path') }

      context 'with no entries' do
        it 'returns that it is an empty directory but does not persist ' \
          'anything' do
          should eq({})
          expect(record.instance_variable_get(:@tree).has_key?('path')).
            to be false
        end
      end

      context 'with path/file.rb already in record' do
        before do
          record.update_dir('path')
          record.update_file('path/file.rb', mtime: 1.1)
        end

        it 'returns that it contains a file' do
          should eq('file.rb' => { mtime: 1.1 })
        end
      end
    end
  end

  describe '#build' do
    let(:dir1) { Pathname('/dir1') }

    before do
      stubs = {
        ::File => %w(lstat realpath),
        ::Dir => %w(entries exist?)
      }

      stubs.each do |klass, meths|
        meths.each do |meth|
          allow(klass).to receive(meth.to_sym) do |*args|
            fail "stub called: #{klass}.#{meth}(#{args.map(&:inspect) * ', '})"
          end
        end
      end
    end

    it 're-inits paths' do
      real_directory('/dir1' => [])
      real_directory('/dir' => [])

      record.update_file('path/file.rb', mtime: 1.1)
      record.build
      expect(record_tree(record)).to eq({})
      expect(record.file_data('path/file.rb')).to be_empty
    end

    let(:foo_stat) { instance_double(::File::Stat, mtime: 1.0, mode: 0644) }
    let(:bar_stat) { instance_double(::File::Stat, mtime: 2.3, mode: 0755) }

    context 'with no subdirs' do
      before do
        real_directory('/dir' => %w(foo bar))
        lstat(file('/dir/foo'), foo_stat)
        lstat(file('/dir/bar'), bar_stat)
        real_directory('/dir2' => [])
      end

      it 'builds record' do
        record.build
        expect(record_tree(record)).to eq(
          '.' => {
            'foo' => { mtime: 1.0, mode: 0644 },
            'bar' => { mtime: 2.3, mode: 0755 }
          }
        )
      end
    end

    context 'with subdir containing files' do
      before do
        real_directory('/dir' => %w(dir1 dir2))
        real_directory('/dir/dir1' => %w(foo))
        real_directory('/dir/dir1/foo' => %w(bar))
        lstat(file('/dir/dir1/foo/bar'))
        real_directory('/dir/dir2' => [])
      end

      it 'builds record'  do
        record.build
        expect(record_tree(record)).to eq(
          '.' => { 'dir1' => {}, 'dir2' => {} },
          'dir1' => { 'foo' => {} },
          'dir1/foo' => { 'bar' => { mtime: 2.3, mode: 0755 } },
          'dir2' => {},
        )
      end
    end

    context 'with subdir containing dirs' do
      before do
        real_directory('/dir' => %w(dir1 dir2))
        real_directory('/dir/dir1' => %w(foo))
        real_directory('/dir/dir1/foo' => %w(bar baz))
        real_directory('/dir/dir1/foo/bar' => [])
        real_directory('/dir/dir1/foo/baz' => [])
        real_directory('/dir/dir2' => [])

        allow(::File).to receive(:realpath) { |path| path }
      end

      it 'builds record'  do
        record.build
        expect(record_tree(record)).to eq(
          '.' => { 'dir1' => {}, 'dir2' => {} },
          'dir1' => { 'foo' => {} },
          'dir1/foo' => { 'bar' => {}, 'baz' => {} },
          'dir1/foo/bar' => {},
          'dir1/foo/baz' => {},
          'dir2' => {},
        )
      end
    end

    context 'with subdir containing symlink to parent' do
      before do
        real_directory('/dir' => %w(dir1 dir2))
        real_directory('/dir/dir1' => %w(foo))
        dir_entries_for('/dir/dir1/foo' => %w(foo))
        lstat(symlink('/dir/dir1/foo', '/dir/dir1'))
        real_directory('/dir/dir2' => [])
      end

      it 'treats the symlink as a regular file' do
        record.build
        expect(record_tree(record)).to eq(
          '.' => { 'dir1' => {}, 'dir2' => {} },
          'dir1' => { 'foo' => { mtime: 2.3, mode: 0755 } },
          'dir2' => {},
        )
      end
    end

    context 'with subdir containing symlinked file' do
      before do
        real_directory('/dir' => %w(dir1 dir2))
        real_directory('/dir/dir1' => %w(foo))
        lstat(file('/dir/dir1/foo'))
        real_directory('/dir/dir2' => %w(foo))
        lstat(symlink('/dir/dir2/foo', '/dir/dir1/foo'))
      end

      it 'treats the symlink as a regular file' do
        record.build
        expect(record_tree(record)).to eq(
          '.' => { 'dir1' => {}, 'dir2' => {} },
          'dir1' => { 'foo' => { mtime: 2.3, mode: 0755 } },
          'dir2' => { 'foo' => { mtime: 2.3, mode: 0755 } },
        )
      end
    end
  end
end
