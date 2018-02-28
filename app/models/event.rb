# frozen_string_literal: true
# == Schema Information
#
# Table name: events
#
#  id               :uuid             not null, primary key
#  user_id          :uuid             not null
#  date             :date             not null
#  start_time       :string           not null
#  description      :text             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  deleted          :boolean          default(FALSE), not null
#  deleted_at       :datetime
#  end_time         :string
#  duration         :integer
#  html_description :text             not null
#  text_description :text             not null
#
# Indexes
#
#  index_events_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#

class Event < ApplicationRecord
  include SoftDeletable

  attribute :ends_previous, :boolean

  belongs_to :user

  has_many :event_hash_tags, inverse_of: :event, dependent: :destroy
  has_many :hash_tags, through: :event_hash_tags

  validates :date, presence: true, timeliness: { date: true }
  validates :start_time, presence: true, timeliness: { time: true }
  validates :end_time, timeliness: { allow_blank: true, time: true, on_or_after: :start_time, if: :start_time? }
  validates :description, length: { maximum: 1000 }, presence: true

  before_save :set_duration, if: -> { start_time_changed? || end_time_changed? }
  before_save :set_hash_tags_from_description, if: :description_changed?
  before_save :set_html_and_text_descriptions, if: :description_changed?

  after_create :set_end_time_on_previous_event, if: :ends_previous?

  def self.longest_duration(limit: nil)
    where.not(duration: nil).order(duration: :desc).limit(limit).pluck(:text_description, :duration).to_h
  end

private

  def set_duration
    return if end_time.blank?
    start  = Time.zone.parse("#{date} #{start_time}")
    finish = Time.zone.parse("#{date} #{end_time}")
    self.duration = (finish - start) / 1.minute
  end

  def set_hash_tags_from_description
    self.hash_tags = HashTagService.new(user, description).hash_tags
  end

  def set_html_and_text_descriptions
    markdown = MarkdownService.new(description, hash_tags: hash_tags)
    self.html_description = markdown.render_html
    self.text_description = markdown.render_text
  end

  def set_end_time_on_previous_event
    previous_event&.update!(end_time: start_time)
  end

  def previous_event
    Event.where(user: user, date: date, end_time: [nil, ''])
      .where(Event.arel_table[:start_time].lt(start_time))
      .order(start_time: :desc).first
  end
end
