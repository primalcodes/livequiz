require "live_quiz/pub_nub"

class Session < ActiveRecord::Base
  belongs_to :quiz
  before_validation :generate_access_key, on: :create
  validates :quiz, presence: true

  has_many :participants, dependent: :destroy
  accepts_nested_attributes_for :participants, reject_if: :all_blank, allow_destroy: true

  validate :participants do 
   	errors.add(:participants, "should not be empty") if self.participants.length <= 0
  end

  after_commit :set_forbidden_access_to_session_channels, on: [:create,:destroy]
  after_commit :allow_full_rights_to_channels_to_quiz, on: [:create]

  def to_param
     access_key
  end

  #  Channel used to send server data to clients
  def server_channel
      "#{access_key}-server"
  end

  #  Channel used to send client data to server
  def client_channel
      "#{access_key}-client"
  end

  def chat_channel
      "#{access_key}-chat"
  end

  def current_question
    self.quiz.questions.rank(:row_order)[current_question_index]
  end

  # Start the quiz session
  def start!
    self.current_question_index = 0
    self.starting_date = DateTime.now()
    send_current_question()
    save()
  end

  def send_current_question
    send_event_with_data('question', {question: current_question.format(:title_with_answers)} )
  end

  def send_event_with_data(event, data)
      cb = lambda { |envelope| puts envelope.message }
      message = {event: event, data: data}
      LiveQuiz::PubNub.client.publish(http_sync: true, message: message, channel: self.server_channel, auth_key: auth_key, callback: cb)
  end

  def started?
    starting_date.present?
  end

  def auth_key
    quiz.access_key
  end

  # Switch to next question
  # Return false if it can't switch because it's the final question
  def switch_to_next_question!

    raise "Quiz has to be started to switch the question" if !started?

    next_question_index = self.current_question_index + 1
    next_question_exist = self.quiz.questions.rank(:row_order)[next_question_index]
    succeeded_to_switch = if !next_question_exist.nil?
                          self.current_question_index = next_question_index
                          send_current_question()
                          save()
                        else
                          false
                        end
    return succeeded_to_switch                  
  end

private

  def generate_access_key
		begin
    		self.access_key= SecureRandom.hex(8)
  		end while self.class.exists?(access_key: access_key)
  end

  def set_forbidden_access_to_session_channels
      [server_channel,client_channel,chat_channel].each do |chan| 
        LiveQuiz::PubNub.client.grant(http_sync: true, channel: chan, read: false, write: false){|envelope|}
      end
  end

  def allow_full_rights_to_channels_to_quiz
      [server_channel,client_channel].each do |chan|
          LiveQuiz::PubNub.client.grant(http_sync: true, channel: chan, presence: chan, auth_key: auth_key, read: true, write: true){|envelope| puts envelope.payload}
      end
  end

end
