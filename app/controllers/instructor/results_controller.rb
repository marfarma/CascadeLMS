class Instructor::ResultsController < Instructor::InstructorBase
  
  before_filter :ensure_logged_in
  before_filter :set_tab

  layout 'noright'
  
  def compare
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless quiz_enabled( @course )
    return unless course_open( @course, :action => 'index' )
    
    @surveys = Quiz.find(:all, :conditions => ["course_id = ? and entry_exit = ?", @course, true], :order => "id asc")

    @all_answer_count_maps = Hash.new
    @all_question_answer_totals = Hash.new
    @all_text_responses = Hash.new

    @surveys.each do |survey|
       @all_answer_count_maps[survey.id], @all_question_answer_totals[survey.id], @all_text_responses[survey.id] =
            aggregate_survey_responses( survey )
    end
    
    quest_arrays = Array.new
    @surveys.each { |sur| quest_arrays << sur.quiz_questions }
    same_length = true
    quest_arrays.each { |arr| same_length = same_length && quest_arrays[0].length==arr.length}
    
    flash[:badnotice] = "The entry/exit surveys are not identical, comparisons are unreliable." if (!same_length)
    # more extensive validation...  
      
    
    puts "ANS: #{@all_answer_count_maps.inspect}"
       
  end

  def survey
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless quiz_enabled( @course )
    return unless course_open( @course, :action => 'index' )
    return unless load_assignment( params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_is_quiz( @assignment )
    @quiz = @assignment.quiz
    
    if ( ! @assignment.quiz.survey ) 
      redirect_to :action => 'quiz', :course => @course, :assignment => @assignment
    end
    
    # map students to 2 columns
    @students = @course.students
    size = @students.length / 2
    @column1 = Array.new
    0.upto(size) { |i| @column1 << @students[i] }
    @column2 = Array.new
    (size+1).upto(@students.length-1) { |i| @column2 << @students[i] }
      
    aggregate_survey_responses( @quiz )  
  end
  
  def survey_question
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless quiz_enabled( @course )
    return unless course_open( @course, :action => 'index' )
    return unless load_assignment( params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_is_quiz( @assignment )
    @quiz = @assignment.quiz
    
    if @quiz.anonymous 
      flash[:badnotice] = "This is an anonymous survey, expanded results are not available."
      redirect_to :action => 'survey', :course => @course, :assignment => @assignment
    end
    
    if ( ! @assignment.quiz.survey ) 
      redirect_to :action => 'quiz', :course => @course, :assignment => @assignment
    end
    
    # load question
    @question = QuizQuestion.find(:first, :conditions => ["id =? and quiz_id = ?", params[:id].to_i, @quiz.id] )
    if @question.nil?
      flash[:badnotice] = "The selected question could not be found."
      return redirect_to :action => 'survey', :course => @course, :assignment => @assignment 
    end
    
    
    @students = @course.students   
    
    # load student answers
    @student_response = Hash.new
    @students.each do |user|
      @student_response[user.id] = Hash.new
      
      attempt = QuizAttempt.find(:first, :conditions => ["quiz_id = ? and user_id = ?", @assignment.quiz.id, user.id])
      unless attempt.nil?
        answers = QuizAttemptAnswer.find(:all, :conditions => ["quiz_attempt_id = ? and quiz_question_id = ?", attempt.id, @question.id])
        
        if @question.text_response
          if answers.length > 0
            @student_response[user.id][@question.id] = answers[0].text_answer 
          end
        else
          answers.each do |answer|
            @student_response[user.id][answer.quiz_question_answer_id] = true
          end
        end
      end
    end
    
    
  end

  def quiz
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless quiz_enabled( @course )
    return unless course_open( @course, :action => 'index' )
    return unless load_assignment( params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_is_quiz( @assignment )
    @quiz = @assignment.quiz
    
    if ( @assignment.quiz.survey ) 
      redirect_to :action => 'survey', :course => @course, :id => @assignment
    end    
    
    @has_text_responses = false
    @quiz.quiz_questions.each { |question| @has_text_responses = @has_text_responses || question.text_response }
    
    if @assignment.grade_item
      # load student grades
      @grades = Hash.new
      entries = GradeEntry.find(:all, :conditions => ["grade_item_id=?", @assignment.grade_item.id ] )
      entries.each do |e|
        @grades[e.user_id] = e.points
      end
    end
    
    @attempts = Hash.new
    @quiz.quiz_attempts.each do |attempt|
      @attempts[attempt.user_id] = true
    end
    
  end
  
  def for_student
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless quiz_enabled( @course )
    return unless course_open( @course, :action => 'index' )
    return unless load_assignment( params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_is_quiz( @assignment )
    @quiz = @assignment.quiz
    
    if @quiz.anonymous 
      flash[:badnotice] = "This is an anonymous survey, expanded results are not available."
      redirect_to :action => 'survey', :course => @course, :assignment => @assignment
    end
    
    # make sure the student exists
    @student = User.find(params[:id])
    if ! @student.student_in_course?( @course.id )
      flash[:badnotice] = "Invalid student record requested."
      redirect_to :action => 'quiz', :course => @course, :assignment => @assignment, :id => nil
    end
    
    unless @assignment.grade_item.nil?
      @grade_entry = GradeEntry.find(:first, :conditions => ["grade_item_id=? and user_id=?", @assignment.grade_item.id, @student.id ] )
      @grade_entry = GradeEntry.new if @grade_entry.nil?
    end
        
    @attempt = QuizAttempt.find(:first, :conditions => ["quiz_id = ? and user_id = ?", @quiz.id, @student.id], :order => "created_at desc")    
    @answer_map = map_existing_quiz_attempt( @attempt ) unless @attempt.nil?
      
    @questions = @quiz.quiz_questions  
       
       
  end


private

  def map_existing_quiz_attempt( quiz_attempt )
    # not first attempt - but also not complete...
    # build the answer set 
    @answer_map = Hash.new
    
    attemptAnswers = QuizAttemptAnswer.find(:all, :conditions => ["quiz_attempt_id = ?", quiz_attempt.id])
    attemptAnswers.each do |attempt|
      # if it is a checkbox question - there might be multiple answers
      if attempt.quiz_question.checkbox
        @answer_map[attempt.quiz_question.id] = Array.new if @answer_map[attempt.quiz_question.id].nil?
        @answer_map[attempt.quiz_question.id] << attempt
      else
        @answer_map[attempt.quiz_question.id] = attempt
      end
    end
    
    return @answer_map
  end

  def aggregate_survey_responses( quiz )
    # we can make some assumptions since 
    @answer_count_map = Hash.new
    @question_answer_total = Hash.new
    @text_responses = Hash.new
    
    quiz.quiz_questions.each do |question|
       
      if question.text_response
        @text_responses[question.id] = Array.new
        responses = QuizAttemptAnswer.find(:all,:conditions => ["quiz_question_id = ?", question.id])
        responses.each do |response|
          @text_responses[question.id] << response.text_answer
        end
      
      else
        total_responses = 0
        question.quiz_question_answers.each do |answer|
          responses  = QuizAttemptAnswer.count(:conditions => ["quiz_question_answer_id = ?", answer.id])
          @answer_count_map[answer.id] = responses
          total_responses = total_responses + responses
        end
        @question_answer_total[question.id] = total_responses
        
      end
    end
    
    return @answer_count_map, @question_answer_total, @text_responses
  end
  
  def set_tab
     @show_course_tabs = true
     @tab = "course_instructor"
  end

  def set_title
     @title = "Quiz - #{@course.title}"
  end

end