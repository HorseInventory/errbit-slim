require 'acceptance/acceptance_helper'

feature "Regeneration api_Key" do
  let(:app) { Fabricate(:app) }
  let(:admin) { Fabricate(:admin) }
  let(:user) { Fabricate(:user) }

  before do
    app && admin
  end

  scenario "an admin change api_key" do
    visit '/'
    log_in admin
    click_link app.name
    click_link I18n.t('apps.show.edit')
    expect do
      click_link I18n.t('apps.fields.regenerate_api_key')
    end.to change {
      app.reload.api_key
    }
    click_link I18n.t('shared.navigation.apps')
    click_link I18n.t('apps.index.new_app')
    expect(page).to_not have_button I18n.t('apps.fields.regenerate_api_key')
  end

  scenario "a user cannot access to edit page" do
    visit '/'
    log_in user
    click_link app.name if page.current_url != app_url(app)
    expect(page).to_not have_button I18n.t('apps.show.edit')
  end
end

feature "Create an application" do
  let(:admin) { Fabricate(:admin) }

  before do
    admin
  end

  scenario "create an app and edit it" do
    visit '/'
    log_in admin
    click_on I18n.t('apps.index.new_app')
    fill_in 'app_name', with: 'My new app'
    click_on I18n.t('apps.new.add_app')
    page.has_content?(I18n.t('controllers.apps.flash.create.success'))
    expect(App.where(name: 'My new app').count).to eq 1
    expect(App.where(name: 'My new app 2').count).to eq 0

    click_on I18n.t('shared.navigation.apps')
    click_on 'My new app'
    click_link I18n.t('apps.show.edit')
    fill_in 'app_name', with: 'My new app 2'
    click_on I18n.t('apps.edit.update')
    page.has_content?(I18n.t('controllers.apps.flash.update.success'))
    expect(App.where(name: 'My new app').count).to eq 0
    expect(App.where(name: 'My new app 2').count).to eq 1
  end

  scenario "create an app and edit it with JavaScript", js: true do
    visit '/'
    log_in admin
    click_on I18n.t('apps.index.new_app')
    fill_in 'app_name', with: 'My new app'

    click_on I18n.t('apps.new.add_app')
    expect(page.has_content?(I18n.t('controllers.apps.flash.create.success'))).to eql true

    click_on I18n.t('shared.navigation.apps')
    click_on 'My new app'
    click_link I18n.t('apps.show.edit')
    click_on I18n.t('apps.edit.update')
    expect(page.has_content?(I18n.t('controllers.apps.flash.update.success'))).to eql true
  end
end
