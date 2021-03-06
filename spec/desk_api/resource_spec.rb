require 'spec_helper'

describe DeskApi::Resource do
  subject do
    @client ||= DeskApi::Client.new DeskApi::CONFIG
  end

  context '#initialize' do
    it 'stores the client' do
      subject.articles.instance_variable_get(:@_client).should eq(subject)
    end

    it 'is not loaded initially' do
      subject.articles.instance_variable_get(:@_loaded).should be_false
    end

    it 'sets up the link to self' do
      subject.articles.href.should_not be_nil
    end
  end

  context '#exec!', :vcr do
    it 'loads the current resource' do
      subject.articles.send(:exec!).instance_variable_get(:@_loaded).should be_true
    end

    it 'can be forced to reload' do
      subject.articles.instance_variable_set(:@_loaded, true)
      subject.should_receive(:get).and_call_original
      subject.articles.send(:exec!, true)
    end
  end

  context '#method_missing', :vcr do
    it 'loads the resource to find a suitable method' do
      articles = subject.articles
      articles.instance_variable_set(:@_loaded, false)
      articles.should_receive(:exec!).and_call_original
      articles.entries
    end

    it 'raises an error if method does not exist' do
      lambda { subject.articles.some_other_method }.should raise_error(NoMethodError)
    end
  end

  context '#by_url', :vcr do
    it 'finds resources by url' do
      subject.articles.by_url('/api/v2/articles/1295677').should be_an_instance_of(DeskApi::Resource)
    end
  end

  context '#get_self' do
    it 'returns the hash for self' do
      subject.articles.get_self.should eq({
        "href" => "/api/v2/articles"
      })
    end
  end

  context '#href' do
    it 'returns the href for self' do
      subject.articles.href.should eq('/api/v2/articles')
    end

    it 'sets the href' do
      res = DeskApi::Resource.new(subject, {
        '_links'=>{'self'=>{'href'=>'/api/v2/cases'}}
      }, true)

      res.href.should eq('/api/v2/cases')
      res.href = '/api/v2/articles'
      res.href.should eq('/api/v2/articles')
    end
  end

  context '#type' do
    it 'returns the resources type' do
      res = DeskApi::Resource.new(subject, {
        '_links'=>{'self'=>{'href'=>'/api/v2/cases','class'=>'page'}}
      }, true)
      res.type.should eq('page')
    end
  end

  context '#search' do
    it 'allows searching on search enabled resources', :vcr do
      subject.articles.search(text: 'Lorem Ipsum').total_entries.should eq(0)
    end
  end

  context '#create' do
    it 'creates a new topic', :vcr do
      topic = subject.topics.create({
        name: 'My new topic'
      }).name.should eq('My new topic')
    end

    it 'throws an error creating a user', :vcr do
      lambda { subject.users.create(name: 'Some User') }.should raise_error(DeskApi::Error::MethodNotAllowed)
    end
  end

  context '#update' do
    it 'updates a topic', :vcr do
      topic = subject.topics.entries.first

      topic.description = 'Some new description'
      topic.update({
        name: 'Updated topic name'
      })

      topic.name.should eq('Updated topic name')
      topic.description.should eq('Some new description')
    end

    it 'throws an error updating a user', :vcr do
      user = subject.users.entries.first
      lambda { user.update(name: 'Some User') }.should raise_error(DeskApi::Error::MethodNotAllowed)
    end

    it 'can update without a hash', :vcr do
      topic = subject.topics.entries.first
      topic.description = 'Another description update.'
      topic.update
      subject.topics.entries.first.description.should eq('Another description update.')
    end
  end

  context '#delete' do
    it 'deletes a resource', :vcr do
      subject.articles.create({
        subject: 'My subject',
        body: 'Some text for this new article',
        _links: {
          topic: subject.topics.entries.first.get_self
        }
      }).delete.should be_true
    end

    it 'throws an error deleting a non deletalbe resource', :vcr do
      user = subject.users.entries.first
      lambda { user.delete }.should raise_error(DeskApi::Error::MethodNotAllowed)
    end
  end

  describe 'embeddable' do
    it 'allows to declare embedds' do
      lambda { subject.cases.embed(:assigned_user) }.should_not raise_error
    end

    it 'changes the url' do
      subject.cases.embed(:assigned_user).href.should eq('/api/v2/cases?embed=assigned_user')
    end

    context 'if you use embed' do
      before do
        VCR.turn_off! ignore_cassettes: true

        @stubs  ||= Faraday::Adapter::Test::Stubs.new
        @client ||= DeskApi::Client.new(DeskApi::CONFIG).tap do |client|
          client.middleware = Proc.new do |builder|
            builder.response :mashify
            builder.response :dates
            builder.response :json, content_type: /application\/json/
            builder.adapter :test, @stubs
          end
        end
      end

      after do
        VCR.turn_on!
      end

      it 'does not load the resource again' do
        times_called = 0
        @stubs.get('/api/v2/cases?embed=assigned_user') do
          times_called += 1
          [
            200,
            { 'content-type' => 'application/json' },
            File.open(File.join(RSpec.configuration.root_path, 'stubs', 'cases_embed_assigned_user.json')).read
          ]
        end

        first_case = @client.cases.embed(:assigned_user).entries.first
        first_case.assigned_user.name.should eq('Thomas Stachl')
        first_case.assigned_user.instance_variable_get(:@_loaded).should be_true
        times_called.should eq(1)
      end

      it 'can be used in finder' do
        @stubs.get('/api/v2/cases/3011?embed=customer') do
          [
            200,
            { 'content-type' => 'application/json' },
            File.open(File.join(RSpec.configuration.root_path, 'stubs', 'case_embed_customer.json')).read
          ]
        end

        customer = @client.cases.find(3011, embed: :customer).customer
        customer.first_name.should eq('Thomas')
        customer = @client.cases.find(3011, embed: [:customer]).customer
        customer.first_name.should eq('Thomas')
      end
    end
  end

  context '#query_params' do
    before do
      @page = DeskApi::Resource.new(subject, {
        '_links'=>{'self'=>{'href'=>'/api/v2/cases?page=2&per_page=50'}}
      }, true)
    end

    it 'allows to get query params from the current resource' do
      @page.send(:query_params_include?, 'page').should eq('2')
      @page.send(:query_params_include?, 'per_page').should eq('50')
    end

    it 'returns nil if param not found' do
      @page.send(:query_params_include?, 'blup').should be_nil
    end
  end

  context '#query_params=' do
    before do
      @page = DeskApi::Resource.new(subject, {
        '_links'=>{'self'=>{'href'=>'/api/v2/cases'}}
      }, true)
    end

    it 'sets query params on the current url' do
      @page.send(:query_params=, { page: 5, per_page: 50 })
      @page.instance_variable_get(:@_definition)['_links']['self']['href'].should eq('/api/v2/cases?page=5&per_page=50')
    end
  end

  context '#get_linked_resource' do
    it 'returns linked resources', :vcr do
      subject.cases.entries.first.customer.should be_an_instance_of(DeskApi::Resource)
    end

    it 'returns nil if link is nil', :vcr do
      subject.articles.next.should be_nil
    end

    it 'saves the linked resource instead of the url', :vcr do
      first_case = subject.cases.entries.first
      first_case.customer.should be_an_instance_of(DeskApi::Resource)
      first_case.instance_variable_get(:@_definition)['_links']['customer'].should be_an_instance_of(DeskApi::Resource)
    end
  end

  context '#page' do
    it 'returns the current page and loads if page not defined', :vcr do
      subject.articles.page.should eq(1)
    end

    it 'sets the page' do
      subject.cases.page(5).page.should eq(5)
    end

    it 'sets the resource to not loaded', :vcr do
      cases = subject.cases.send(:exec!)
      cases.page(5).instance_variable_get(:@_loaded).should be_false
    end

    it 'keeps the resource as loaded', :vcr do
      cases = subject.cases.send(:exec!)
      cases.page(1).instance_variable_get(:@_loaded).should be_true
    end
  end

  context '#find' do
    it 'loads the requested resource', :vcr do
      subject.cases.find(3065).subject.should eq('Testing the Tank again')
    end

    it 'has an alias by_id', :vcr do
      subject.cases.find(3065).subject.should eq('Testing the Tank again')
    end
  end
end