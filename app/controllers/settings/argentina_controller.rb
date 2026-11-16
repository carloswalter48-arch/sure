# frozen_string_literal: true

class Settings::ArgentinaController < ApplicationController
  def sync
    Argentina::SyncJob.perform_later
    redirect_to settings_preferences_path, notice: t(".queued")
  end
end
