require 'rails_helper'
require 'couchbase'
require 'securerandom'

RSpec.describe User, type: :model do
  let(:current_user) { User.new(id: 'current-user-id', username: 'currentuser', email: 'currentuser@example.com', password_digest: BCrypt::Password.create('password'), bio: 'Current user bio', image: 'current_image.png') }
  let(:other_user) { User.new(id: 'other-user-id', username: 'otheruser', email: 'otheruser@example.com', password_digest: BCrypt::Password.create('password'), bio: 'Other user bio', image: 'other_image.png') }
  let(:bucket) { instance_double(Couchbase::Bucket) }
  let(:collection) { instance_double(Couchbase::Collection) }
  let(:cluster) { instance_double(Couchbase::Cluster) }
  let(:lookup_in_result) { instance_double(Couchbase::Collection::LookupInResult, content: [], exists?: true) }

  before do
    allow(Rails.application.config).to receive(:couchbase_bucket).and_return(bucket)
    allow(Rails.application.config).to receive(:couchbase_cluster).and_return(cluster)
    allow(bucket).to receive(:default_collection).and_return(collection)
    allow(collection).to receive(:lookup_in).with(current_user.id, anything).and_return(lookup_in_result)
    allow(collection).to receive(:lookup_in).with(other_user.id, anything).and_return(lookup_in_result)
  end

  describe '#save' do
    context 'when the user is saved with an ID' do
      it 'correctly saves a new user to the Couchbase bucket with a unique ID if not already set' do
        user = User.new(username: 'testuser', email: 'test@example.com', password_digest: 'password')
        allow(SecureRandom).to receive(:uuid).and_return('unique-id')
        expect(collection).to receive(:upsert).with('unique-id', user.to_hash)

        user.save

        expect(user.id).to eq('unique-id')
      end
    end

    context 'when Couchbase upsert fails' do
      it 'raises an error' do
        user = User.new(username: 'testuser', email: 'test@example.com', password_digest: 'password')
        allow(SecureRandom).to receive(:uuid).and_return('unique-id')
        allow(collection).to receive(:upsert).and_raise(Couchbase::Error::Timeout)

        expect { user.save }.to raise_error(Couchbase::Error::Timeout)
      end
    end
  end

  describe '.find_by_email' do
    context 'when a user is found with the given email'
      it 'returns a User object when a user with the given email exists in the Couchbase bucket' do
        email = 'test@example.com'
        query_result = instance_double(Couchbase::Cluster::QueryResult, rows: [{ "_default" => {'username' => 'testuser', 'email' => email, 'password_digest' => 'password'}, 'id' => 'user-id' }])
        allow(cluster).to receive(:query).and_return(query_result)

        user = User.find_by_email(email)

        expect(user).to be_a(User)
        expect(user.id).to eq('user-id')
        expect(user.email).to eq(email)
      end
    end

    context 'when no user with the given email exists' do
      it 'returns nil' do
        email = 'nonexistent@example.com'
        query_result = instance_double(Couchbase::Cluster::QueryResult, rows: [])
        allow(cluster).to receive(:query).and_return(query_result)

        user = User.find_by_email(email)

        expect(user).to be_nil
      end
    end

    context 'when Couchbase query fails' do
      it 'raises an error' do
        email = 'test@example.com'
        allow(cluster).to receive(:query).and_raise(Couchbase::Error::Timeout)

        expect { User.find_by_email(email) }.to raise_error(Couchbase::Error::Timeout)
      end
    end

  describe '#follow' do
    context 'when the user is found to be added' do
      it 'correctly adds a user to the following list of another user' do
        expect(collection).to receive(:mutate_in).with(
          'current-user-id',
          [an_instance_of(Couchbase::MutateInSpec).and(
            satisfy { |spec| spec.instance_variable_get(:@param) == "\"other-user-id\"" && spec.instance_variable_get(:@path) == 'following' }
          )]
        )

        current_user.follow(other_user)
      end
    end
  end
end
