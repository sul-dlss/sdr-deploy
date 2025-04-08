# frozen_string_literal: true

# Container for git tag subcommands
class GitTagCLI < Thor
  class_option :skip_non_cocina,
               type: :boolean,
               default: false,
               desc: 'Include only repos depending on new Cocina models releases',
               aliases: '-c'

  option :message,
         desc: 'Message to describe a newly created tag',
         aliases: '-m'
  desc 'create TAG_NAME', 'Create a git tag locally and remotely'
  def create(tag_name)
    RepoUpdater.update(repos: repositories)
    Tagger.create(tag_name:, tag_message: options.fetch(:message, 'created by sdr-deploy'), repos: repositories)
  end

  desc 'verify TAG_NAME', 'Verify a git tag exists remotely'
  def verify(tag_name)
    RepoUpdater.update(repos: repositories)
    Tagger.verify(tag_name:, repos: repositories)
  end

  desc 'delete TAG_NAME', 'Delete a git tag locally and remotely'
  def delete(tag_name)
    RepoUpdater.update(repos: repositories)
    Tagger.delete(tag_name:, repos: repositories)
  end

  private

  def repositories
    if parent_options[:skip_non_cocina]
      Settings.repositories.select(&:cocina_models_update)
    else
      Settings.repositories
    end
  end
end
