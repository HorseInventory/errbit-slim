require 'acceptance/acceptance_helper'

feature "App API keys" do
  let!(:app) { Fabricate(:app) }
  let(:admin) { Fabricate(:admin) }
  let(:user) { Fabricate(:user) }

  scenario "an admin regenerates the API key" do
    log_in admin
    click_link app.name
    click_link I18n.t('apps.show.edit')
    expect do
      click_link(I18n.t('apps.fields.regenerate_api_key'))
    end.to(change { app.reload.api_key })
    click_link I18n.t('shared.navigation.apps')
    click_link I18n.t('apps.index.new_app')
    expect(page).to_not(have_link(I18n.t('apps.fields.regenerate_api_key')))
  end

  scenario "a regular user has no edit link" do
    log_in user
    visit app_path(app)
    expect(page).to_not(have_link(I18n.t('apps.show.edit')))
  end
end

feature "App creation and editing" do
  let(:admin) { Fabricate(:admin) }

  scenario "an admin creates and renames an app", js: true do
    log_in admin
    click_on I18n.t('apps.index.new_app')
    fill_in 'app_name', with: 'My new app'
    click_on I18n.t('apps.new.add_app')
    expect(page).to(have_content(I18n.t('controllers.apps.flash.create.success')))
    expect(App.where(name: 'My new app').count).to(eq(1))
    expect(App.where(name: 'My new app 2').count).to(eq(0))

    click_on I18n.t('shared.navigation.apps')
    click_on 'My new app'
    click_link I18n.t('apps.show.edit')
    fill_in 'app_name', with: 'My new app 2'
    click_on I18n.t('apps.edit.update')
    expect(page).to(have_content(I18n.t('controllers.apps.flash.update.success')))
    expect(App.where(name: 'My new app').count).to(eq(0))
    expect(App.where(name: 'My new app 2').count).to(eq(1))
  end
end
