class NotesController < ApplicationController
  before_action :set_dataset
  before_action :set_note, only: %i[show edit update destroy]

  def index
    @notes = @dataset.notes
  end

  def show
  end

  def new
    @note = @dataset.notes.build(author: current_user.email)
  end

  def create
    @note = @dataset.notes.build(note_params)

    if @note.save
      redirect_to dataset_notes_path(@dataset), notice: "Note was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @note.update(note_params)
      redirect_to dataset_notes_path(@dataset), notice: "Note was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @note.destroy!
    redirect_to dataset_notes_path(@dataset), notice: "Note was successfully deleted."
  end

  private

  def set_dataset
    @dataset = Dataset.find_by!(key: params[:dataset_id])
    authorize! :review_versions, @dataset
  end

  def set_note
    @note = @dataset.notes.find(params[:id])
  end

  def note_params
    params.require(:note).permit(:body, :author)
  end
end
