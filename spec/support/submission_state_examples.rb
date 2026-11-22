RSpec.shared_examples 'rejects unsafe submission state' do |store, send_order|
  [0o770, 0o707, 0o1777].each do |mode|
    it "rejects a writable submission directory with mode #{mode.to_s(8)} before sending an order" do
      directory = store.state_directory
      File.chmod(mode, directory)

      expect { run_command }.to raise_error(Thor::Error, "Unsafe submission state directory: #{directory}")
      expect(private_client).not_to have_received(send_order)
      expect(Dir.children(directory)).to be_empty
    ensure
      File.chmod(0o700, directory)
    end
  end

  it 'rejects a writable ancestor of a private submission directory before sending an order' do
    parent = File.join(store.state_directory, 'shared')
    directory = File.join(parent, 'submissions')
    Dir.mkdir(parent, 0o700)
    File.chmod(0o770, parent)
    Dir.mkdir(directory, 0o700)
    allow(store).to receive(:state_directory).and_return(directory)

    expect { run_command }.to raise_error(Thor::Error, "Unsafe submission state directory: #{parent}")
    expect(private_client).not_to have_received(send_order)
    expect(Dir.children(directory)).to be_empty
  end

  it 'rejects a symbolic link in the state path before sending an order' do
    root = store.state_directory
    target = File.join(root, 'target')
    link = File.join(root, 'redirect')
    Dir.mkdir(target, 0o700)
    File.symlink(target, link)
    allow(store).to receive(:state_directory).and_return(File.join(link, 'submissions'))

    expect { run_command }.to raise_error(Thor::Error, "Unsafe submission state directory: #{link}")
    expect(private_client).not_to have_received(send_order)
    expect(Dir.children(target)).to be_empty
  end

  it 'refuses to read a submission record through a symbolic link' do
    directory = store.state_directory
    expect { run_submission_command }.to output(/order|position/i).to_stdout
    entry = Dir.children(directory).find { |name| !name.end_with?('.lock') }
    record = File.join(directory, entry)
    target = File.join(directory, 'redirected-record')
    File.rename(record, target)
    File.symlink(target, record)

    expect { run_submission_command }.to raise_error(Errno::ELOOP)
    expect(private_client).to have_received(send_order).once
  end

  it 'rejects a submission directory owned by another account before sending an order' do
    directory = store.state_directory
    other_owner = instance_double(File::Stat, directory?: true, uid: Process.euid + 1)
    allow(File).to receive(:lstat).and_call_original
    allow(File).to receive(:lstat).with(Pathname.new(directory)).and_return(other_owner)

    expect { run_command }.to raise_error(Thor::Error, "Unsafe submission state directory: #{directory}")
    expect(private_client).not_to have_received(send_order)
    expect(Dir.children(directory)).to be_empty
  end
end
