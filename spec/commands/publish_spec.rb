require 'spec_helper'

describe Cli::Publish do
  include_context 'tmp_dirs'

  around_with_fixture_repo do |spec|
    spec.run
  end

  let(:sections) do
    [
        {'repository' => {'name' => 'fantastic/dogs-repo', 'ref' => 'dog-sha'}, 'directory' => 'dogs', 'subnav_template' => 'dogs'},
        {'repository' => {'name' => 'fantastic/my-docs-repo', 'ref' => 'my-docs-sha'}, 'directory' => 'foods/sweet', 'subnav_template' => 'fruits'},
        {'repository' => {'name' => 'fantastic/my-other-docs-repo', 'ref' => 'my-other-sha'}, 'directory' => 'foods/savory', 'subnav_template' => 'vegetables'}
    ]
  end

  let(:config) do
    double('Configuration').tap do |d|
      allow(d).to receive(:has_option?)
      allow(d).to receive(:sections) { sections }
      allow(d).to receive(:pdf_index)
      allow(d).to receive(:public_host)
      allow(d).to receive(:book_repo) { 'fantastic/fixture-book-title' }
    end
  end

  let(:logger) { NilLogger.new }
  let(:publish_command) { Cli::Publish.new(logger, config) }
  let(:git_client) { GitClient.new(logger) }

  before do
    allow(ProgressBar).to receive(:create).and_return(double(increment: nil))
    sections.each { |s| stub_github_commits(name: s['repository']['name']) }
    Spider.any_instance.stub(:generate_sitemap)
  end

  context 'local' do
    around do |spec|
      WebMock.disable_net_connect!(:allow_localhost => true)
      spec.run
      WebMock.disable_net_connect!
    end

    let(:dogs_index) { File.join('final_app', 'public', 'dogs', 'index.html') }

    def response_for(page)
      publish_command.run ['local']

      response = nil
      ServerDirector.new(logger, directory: 'final_app').use_server do |port|
        uri = URI "http://localhost:#{port}/#{page}"
        req = Net::HTTP::Get.new(uri.path)
        response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
      end
      response
    end

    it 'runs idempotently' do
      silence_io_streams do
        publish_command.run ['local'] # Run Once

        expect do
          publish_command.run ['local'] # Run twice
        end.not_to change { File.exist? dogs_index }.from(true).to(false)
      end
    end

    it 'creates some static HTML' do
      publish_command.run ['local']

      index_html = File.read dogs_index
      index_html.should include 'Woof'
    end

    it 'respects a redirects file' do
      redirect_rules = "r301 '/index.html', '/dogs/index.html'"

      expect { File.write('redirects.rb', redirect_rules) }.to change {
        response_for('index.html')
      }.from(Net::HTTPSuccess).to(Net::HTTPMovedPermanently)
    end

    context 'when provided a layout repo' do
      before do
        allow(config).to receive(:has_option?).with('layout_repo').and_return true
        allow(config).to receive(:layout_repo).and_return 'such-org/layout-repo'
      end

      it 'passes the provided repo as master_middleman_dir' do
        fake_publisher = double(:publisher)
        expect(Publisher).to receive(:new).and_return fake_publisher

        expect(fake_publisher).to receive(:publish) do |args|
          expect(args[:master_middleman_dir]).to match('layout-repo')
        end

        publish_command.run ['local']
      end
    end
  end

  context 'github' do

    before do
      allow(git_client).to receive(:archive_link)
      stub_github_for git_client, 'fantastic/dogs-repo', 'dog-sha'
      stub_github_for git_client, 'fantastic/my-docs-repo', 'my-docs-sha'
      stub_github_for git_client, 'fantastic/my-other-docs-repo', 'my-other-sha'
      allow(GitClient).to receive(:new).and_return(git_client)
    end

    it 'creates some static HTML' do
      sections.each { |s| stub_github_commits(name: s['repository']['name'], sha: s['repository']['ref']) }

      publish_command.run ['github']

      index_html = File.read File.join('final_app', 'public', 'foods', 'sweet', 'index.html')
      index_html.should include 'This is a Markdown Page'
    end

    context 'when a tag is provided' do
      let(:desired_tag) { 'foo-1.7.12' }
      let(:cli_args) { ['github', desired_tag] }
      let(:fixture_repo_name) { 'fantastic/fixture-book-title' }

      it 'gets the book at that tag' do
        sections.each { |s| stub_github_commits(name: s['repository']['name'], sha: desired_tag) }

        stub_github_for git_client, 'fantastic/dogs-repo', desired_tag
        stub_github_for git_client, 'fantastic/my-docs-repo', desired_tag
        stub_github_for git_client, 'fantastic/my-other-docs-repo', desired_tag

        zipped_repo_url = "https://github.com/#{fixture_repo_name}/archive/#{desired_tag}.tar.gz"

        zipped_repo = RepoFixture.tarball 'fantastic/book'.split('/').last, desired_tag
        stub_request(:get, zipped_repo_url).to_return(
            :body => zipped_repo, :headers => {'Content-Type' => 'application/x-gzip'}
        )

        stub_refs_for_repo(fixture_repo_name, [desired_tag])

        expect(git_client).to receive(:archive_link).with(fixture_repo_name, ref: desired_tag).once.and_return zipped_repo_url

        publish_command.run cli_args
      end

      pending 'when a constituent repository does not have the tag'
      pending 'when a book does not have the tag'
    end

    context 'when provided a layout repo' do
      before do
        allow(config).to receive(:has_option?).with('layout_repo').and_return true
        allow(config).to receive(:layout_repo).and_return 'such-org/layout-repo'

        mock_github_for(git_client, 'such-org/layout-repo')
        allow(GitClient).to receive(:new).and_return(git_client)
      end

      it 'passes the provided repo as master_middleman_dir' do
        fake_publisher = double(:publisher)
        expect(Publisher).to receive(:new).and_return fake_publisher

        expect(fake_publisher).to receive(:publish) do |args|
          expect(args[:master_middleman_dir]).to match('layout-repo')
        end

        publish_command.run ['github']
      end
    end
  end

  context 'when a pdf is specified' do
    pending 'creates the pdf'
  end

  describe 'invalid arguments' do
    it 'raises Cli::InvalidArguments' do
      expect {
        publish_command.run ['blah', 'blah', 'whatever']
      }.to raise_error(Cli::InvalidArguments)

      expect {
        publish_command.run []
      }.to raise_error(Cli::InvalidArguments)
    end
  end

  describe 'publication arguments' do
    let(:all_these_arguments_and_such) do
      {sections: [{"repository" => {"name" => "fantastic/dogs-repo", "ref" => "dog-sha"},
                   "directory" => "dogs",
                   "subnav_template" => "dogs"},
                  {"repository" => {"name" => "fantastic/my-docs-repo", "ref" => "my-docs-sha"},
                   "directory" => "foods/sweet",
                   "subnav_template" => "fruits"},
                  {"repository" =>
                       {"name" => "fantastic/my-other-docs-repo", "ref" => "my-other-sha"},
                   "directory" => "foods/savory",
                   "subnav_template" => "vegetables"}],
       output_dir: anything,
       master_middleman_dir: anything,
       final_app_dir: anything,
       pdf: nil,
       verbose: false,
       pdf_index: nil,
       local_repo_dir: anything,
       host_for_sitemap: nil}
    end

    it 'are appropriate' do
      fake_publisher = double(:publisher)
      expect(Publisher).to receive(:new).and_return fake_publisher
      expect(fake_publisher).to receive(:publish).with all_these_arguments_and_such
      publish_command.run ['local']
    end
  end
end
