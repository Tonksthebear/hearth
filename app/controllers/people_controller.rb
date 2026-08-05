class PeopleController < ApplicationController
  before_action :set_person, only: %i[ show edit update ]

  def index
    @people = Current.household.people.includes(:user).order(:name)
  end

  def show
    @person_overview = Person::Overview.current(household: Current.household, person: @person)
  end

  def new
    @person = Current.household.people.build
    prepare_login_fields
  end

  def create
    @person = Current.household.people.build(person_params)

    if @person.save
      redirect_to people_path, notice: "#{@person.name} was added.", status: :see_other
    else
      prepare_login_fields
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prepare_login_fields
  end

  def update
    if @person.update(person_params)
      redirect_to people_path, notice: "#{@person.name} was updated.", status: :see_other
    else
      prepare_login_fields
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_person
      @person = Current.household.people.find(params[:id])
    end

    def person_params
      permitted = [ :name ]
      permitted << { user_attributes: [ :email_address, :password, :password_confirmation ] } unless @person&.user&.persisted?
      params.expect(person: permitted)
    end

    def prepare_login_fields
      @person.build_user unless @person.user
    end
end
