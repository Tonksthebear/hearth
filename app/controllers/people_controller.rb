class PeopleController < ApplicationController
  before_action :set_person, only: %i[ edit update ]

  def index
    @people = Current.household.people.order(:name)
  end

  def new
    @person = Current.household.people.build
  end

  def create
    @person = Current.household.people.build(person_params)

    if @person.save
      redirect_to people_path, notice: "#{@person.name} was added.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @person.update(person_params)
      redirect_to people_path, notice: "#{@person.name} was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_person
      @person = Current.household.people.find(params[:id])
    end

    def person_params
      params.expect(person: [ :name ])
    end
end
