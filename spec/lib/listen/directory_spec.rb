include Listen

RSpec.describe Directory do
  def fake_file_stat(name)
    stat = instance_double(::File::Stat, directory?: false)
    allow(::File).to receive(:lstat).with(name).and_return(stat)
  end

  def fake_dir_stat(name)
    stat = instance_double(::File::Stat, directory?: true)
    allow(::File).to receive(:lstat).with(name).and_return(stat)
  end

  def file_system(s = nil)
    @file_system = s unless s.nil?
    @file_system ||= {}
  end

  def dir_entries(s = nil)
    @dir_entries = [true, s] unless s.nil?
    @dir_entries ||= [true, {}]
  end

  def expect_file_update(path)
    expect(record).to receive(:update_file).with(path).
      and_return(dir_entries[1].key?(path))
  end

  def expect_dir_update(path)
    expect(record).to receive(:update_dir).with(path).
      and_return(dir_entries[1].key?(path))
  end

  let(:record) do
    r = instance_double(
      Record,
      root: '/dir',
      unset_path: nil
    )
    allow(r).to receive(:dir_entries) do
      dir_entries
    end
    r
  end

  let(:snapshot) { instance_double(Change, record: record, invalidate: nil) }

  let(:options) { { option: 'value' } }

  before do
    root = Pathname.new('/dir')
    orig_new = Pathname.method(:new)
    allow(Pathname).to receive(:new) do |path|
      o = orig_new.call(path)
      allow(o).to receive(:children) do
        entries = file_system[o.relative_path_from(root).to_s]
        fail Errno::ENOENT if entries.nil?
        (entries || []).map do |child|
          o + child
        end
      end
      o
    end

    allow(::File).to receive(:lstat) do |*args|
      fail "Not stubbed: File.lstat(#{args.map(&:inspect) * ','})"
    end
  end

  context '#scan with recursive off' do
    context 'with empty record' do
      it 'invalidates added directory trees' do
        file_system('.' => ['subdir'])
        fake_dir_stat '/dir/subdir'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(:tree, 'subdir', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates added files' do
        file_system('.' => ['file.rb'])
        fake_file_stat '/dir/file.rb'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(:file, 'file.rb', options)
        described_class.scan(snapshot, '.', options, false)
      end
    end

    context 'with populated record' do
      it 'invalidates added directory trees' do
        dir_entries('dir1' => {}, 'dir2' => {})
        file_system('.' => ['dir1', 'dir2', 'dir3'])
        fake_dir_stat '/dir/dir1'
        fake_dir_stat '/dir/dir2'
        fake_dir_stat '/dir/dir3'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(:tree, 'dir3', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates removed directory trees' do
        dir_entries('dir1' => {}, 'dir2' => {})
        file_system('.' => ['dir2'])
        fake_dir_stat '/dir/dir2'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(:tree, 'dir1', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates both added and removed trees' do
        dir_entries('dir1' => {}, 'dir2' => {})
        file_system('.' => ['dir2', 'dir3'])
        fake_dir_stat '/dir/dir2'
        fake_dir_stat '/dir/dir3'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(:tree, 'dir1', options)
        expect(snapshot).to receive(:invalidate).with(:tree, 'dir3', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates all files including added files' do
        dir_entries('file2.rb' => { mtime: 1.1 })
        file_system('.' => ['file1.rb', 'file2.rb'])
        fake_file_stat '/dir/file1.rb'
        fake_file_stat '/dir/file2.rb'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(
          :file, 'file1.rb', options)
        expect(snapshot).to receive(:invalidate).with(
          :file, 'file2.rb', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates all files including removed files' do
        dir_entries('file1.rb' => { mtime: 1.1 }, 'file2.rb' => { mtime: 1.1 })
        file_system('.' => ['file1.rb'])
        fake_file_stat '/dir/file1.rb'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(
          :file, 'file1.rb', options)
        expect(snapshot).to receive(:invalidate).with(
          :file, 'file2.rb', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates all files including both added and removed files' do
        dir_entries('file1.rb' => { mtime: 1.1 }, 'file2.rb' => { mtime: 1.1 })
        file_system('.' => ['file1.rb', 'file3.rb'])
        fake_file_stat '/dir/file1.rb'
        fake_file_stat '/dir/file3.rb'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).with(
          :file, 'file1.rb', options)
        expect(snapshot).to receive(:invalidate).with(
          :file, 'file2.rb', options)
        expect(snapshot).to receive(:invalidate).with(
          :file, 'file3.rb', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates directory trees that are now files' do
        dir_entries('ambiguous' => {})
        file_system('.' => ['ambiguous'])
        fake_file_stat '/dir/ambiguous'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).ordered.with(
          :file, 'ambiguous', options)
        expect(snapshot).to receive(:invalidate).ordered.with(
          :tree, 'ambiguous', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates files that are now directory trees' do
        dir_entries('ambiguous' => { mtime: 1.1 })
        file_system('.' => ['ambiguous'])
        fake_dir_stat '/dir/ambiguous'

        expect_dir_update('.')
        expect(snapshot).to receive(:invalidate).ordered.with(
          :tree, 'ambiguous', options)
        expect(snapshot).to receive(:invalidate).ordered.with(
          :file, 'ambiguous', options)
        described_class.scan(snapshot, '.', options, false)
      end

      it 'invalidates all previous directory contents if the directory is ' \
        'removed' do
        dir_entries(
          'file1.rb' => { mtime: 1.1 },
          'dir1'     => {},
          'file2.rb' => { mtime: 1.1 },
        )
        fake_file_stat '/dir/file1.rb'
        fake_dir_stat '/dir/dir1'
        fake_file_stat '/dir/file2.rb'

        expect(snapshot).to receive(:invalidate).ordered.with(
          :file, 'file1.rb', options)
        expect(snapshot).to receive(:invalidate).ordered.with(
          :tree, 'dir1', options)
        expect(snapshot).to receive(:invalidate).ordered.with(
          :file, 'file2.rb', options)
        described_class.scan(snapshot, '.', options, false)
      end
    end
  end

  context '#scan with recursive on' do

  end
end
