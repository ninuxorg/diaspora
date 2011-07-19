require 'spec_helper'

describe Services::Google do

  before do
    @user = alice
    @service = Services::Google.new(:access_token => "yeah")
    @user.services << @service
  end

  context 'finder' do

    before do
      @user2 = Factory.create(:user_with_aspect)
      @user2_fb_id = '820651'
      @user2_fb_name = 'Maxwell Salzberg'
      @user2_fb_photo_url = "http://cdn.fn.com/pic1.jpg"
      @user2_service = Services::Facebook.new(:uid => @user2_fb_id, :access_token => "yo")
      @user2.services << @user2_service
      @fb_list_hash =  <<JSON
      {
        "data": [
          {
            "name": "#{@user2_fb_name}",
            "id": "#{@user2_fb_id}",
            "picture": "#{@user2_fb_photo_url}"
          },
          {
            "name": "Person to Invite",
            "id": "abc123",
            "picture": "http://cdn.fn.com/pic1.jpg"
          }
        ]
      }
JSON
      stub_request(:get, "https://graph.facebook.com/me/friends?fields[]=name&fields[]=picture&access_token=yeah").
        to_return(:body => @fb_list_hash)
    end

    describe '#save_friends' do
      it 'requests a friend list' do
        @service.save_friends
        WebMock.should have_requested(:get, "https://graph.facebook.com/me/friends?fields[]=name&fields[]=picture&access_token=yeah")
      end

      it 'creates a service user objects' do
        lambda{
          @service.save_friends
        }.should change(ServiceUser, :count).by(2)
      end
    end

    describe '#finder' do
      it 'does a synchronous call if it has not been called before' do
        @service.should_receive(:save_friends)
        @service.finder
      end
      it 'dispatches a resque job' do
        Resque.should_receive(:enqueue).with(Job::UpdateServiceUsers, @service.id)
        su2 = ServiceUser.create(:service => @user2_service, :uid => @user2_fb_id, :name => @user2_fb_name, :photo_url => @user2_fb_photo_url)
        @service.service_users = [su2]
        @service.finder
      end
      context 'opts' do
        it 'only local does not return people who are remote' do
          @service.save_friends
          @service.finder(:local => true).each{|su| su.person.should == @user2.person}
        end

        it 'does not return people who are remote' do
          @service.save_friends
          @service.finder(:remote => true).each{|su| su.person.should be_nil}
        end

        it 'does not return wrong service objects' do
          su2 = ServiceUser.create(:service => @user2_service, :uid => @user2_fb_id, :name => @user2_fb_name, :photo_url => @user2_fb_photo_url)
          su2.person.should == @user2.person

          @service.finder(:local => true).each{|su| su.service.should == @service}
          @service.finder(:remote => true).each{|su| su.service.should == @service}
          @service.finder.each{|su| su.service.should == @service}
        end
      end
    end
  end
end