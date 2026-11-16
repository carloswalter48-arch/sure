# frozen_string_literal: true

class Argentina::SyncJob < ApplicationJob
  queue_as :scheduled

  def perform
    Argentina::Sync.call
  end
end
