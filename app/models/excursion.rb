# Copyright 2011-2012 Universidad Politécnica de Madrid and Agora Systems S.A.
#
# This file is part of ViSH (Virtual Science Hub).
#
# ViSH is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ViSH is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with ViSH.  If not, see <http://www.gnu.org/licenses/>.
require 'builder'

class Excursion < ActiveRecord::Base
  include SocialStream::Models::Object
  has_many :excursion_contributors, :dependent => :destroy
  has_many :contributors, :class_name => "Actor", :through => :excursion_contributors

  validates_presence_of :json
  after_save :parse_for_meta
  before_save :fix_relation_ids_drafts
  after_destroy :remove_scorm
  after_destroy :remove_pdf
  after_save :fix_post_activity_nil

  define_index do
    activity_object_index
    indexes excursion_type
    has slide_count
    has draft
    has activity_object.like_count, :as => :like_count
    has activity_object.visit_count, :as => :visit_count
  end

  ####################
  ## OAI-PMH Management
  ####################
  def oai_dc_identifier
    Rails.application.routes.url_helpers.excursion_url(:id => self.id)
  end

  def oai_dv_title
    title
  end

  def oai_dv_description
    description
  end

  def oai_dv_creator
    author.name
  end




  ####################
  ## JSON Management
  ####################

  def to_json(options=nil)
    json
  end


  ####################
  ## SCORM Management
  ####################

  def self.createSCORM(filePath,fileName,json,excursion,controller)
    require 'zip/zip'
    require 'zip/zipfilesystem'

    # filePath = "#{Rails.root}/public/scorm/excursions/"
    # fileName = self.id
    # json = JSON(self.json)
    t = File.open("#{filePath}#{fileName}.zip", 'w')

    #Generate Manifest and HTML file
    Zip::ZipOutputStream.open(t.path) do |zos|
      xml_manifest = Excursion.generate_scorm_manifest(json,excursion)
      zos.put_next_entry("imsmanifest.xml")
      zos.print xml_manifest.target!()

      zos.put_next_entry("excursion.html")
      zos.print controller.render_to_string "show.scorm.erb", :locals => {:excursion=>excursion, :json => json}, :layout => false  
    end

    #Copy SCORM assets (image, javascript and css files)
    dir = "#{Rails.root}/vendor/plugins/vish_editor/app/scorm"
    zip_folder(t.path,dir,nil)

    #Add theme
    themesPath = "#{Rails.root}/vendor/plugins/vish_editor/app/assets/images/themes/"
    theme = "theme1" #Default theme
    if json["theme"] and File.exists?(themesPath + json["theme"])
      theme = json["theme"]
    end
    #Copy excursion theme
    zip_folder(t.path,"#{Rails.root}/vendor/plugins/vish_editor/app/assets",themesPath + theme)

    t.close
  end

  def self.zip_folder(zipFilePath,root,dir)
    unless dir 
      dir = root
    end

    #Get subdirectories
    Dir.chdir(dir)
    subdir_list=Dir["*"].reject{|o| not File.directory?(o)}
    subdir_list.each do |subdirectory|
      subdirectory_path = "#{dir}/#{subdirectory}"
      zip_folder(zipFilePath,root,subdirectory_path)
    end

    #Look for files
    Zip::ZipFile.open(zipFilePath, Zip::ZipFile::CREATE) { |zipfile|
      Dir.foreach(dir) do |item|
        item_path = "#{dir}/#{item}"
        if File.file?item_path
          rpath = String.new(item_path)
          rpath.slice! root + "/"
          zipfile.add(rpath,item_path)
        end
      end
    }
  end

  # Metadata based on LOM (Learning Object Metadata) standard
  # LOM final draft: http://ltsc.ieee.org/wg12/files/LOM_1484_12_1_v1_Final_Draft.pdf
  def self.generate_scorm_manifest(ejson,excursion)
    if excursion and !excursion.id.nil?
      identifier = excursion.id.to_s
    elsif (ejson["vishMetadata"] and ejson["vishMetadata"]["id"])
      identifier = ejson["vishMetadata"]["id"].to_s
    else
      identifier = "TmpSCORM_" + (Site.current.config["tmpJSONcount"].nil? ? "1" : Site.current.config["tmpJSONcount"].to_s)
    end

    myxml = ::Builder::XmlMarkup.new(:indent => 2)
    myxml.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
    myxml.manifest("identifier"=>"VISH_VIRTUAL_EXCURSION_" + identifier,
      "version"=>"1.0",
      "xsi:schemaLocation"=>"http://www.imsglobal.org/xsd/imscp_v1p1.xsd http://www.adlnet.org/xsd/adlcp_v1p3.xsd http://www.adlnet.org/xsd/adlnav_v1p3.xsd http://www.adlnet.org/xsd/adlseq_v1p3.xsd http://www.imsglobal.org/xsd/imsss_v1p0.xsd http://ltsc.ieee.org/xsd/LOM/lom.xsd",
      "xmlns:adlcp"=>"http://www.adlnet.org/xsd/adlcp_v1p3",
      "xmlns:xsi"=>"http://www.w3.org/2001/XMLSchema-instance",
      "xmlns"=>"http://www.imsglobal.org/xsd/imscp_v1p1",
      "xmlns:imsss"=>"http://www.imsglobal.org/xsd/imsss",
      "xmlns:lom"=>"http://ltsc.ieee.org/xsd/LOM/lom.xsd" ) do

      myxml.metadata() do
        myxml.schema("ADL SCORM")
        myxml.schemaversion("CAM 1.3")

        myxml.lom do
          myxml.general do
            myxml.identifier("VISH_VIRTUAL_EXCURSION_"+ identifier)
            myxml.title do
              if ejson["title"]
                myxml.langstring(ejson["title"])
              else
                myxml.langstring("Untitled")
              end
            end
            if ejson["language"]
              myxml.language(ejson["language"])
            end
            myxml.description do
              if ejson["description"]
                myxml.langstring(ejson["description"])
              elsif ejson["title"]
                myxml.langstring(ejson["title"] + ". A Virtual Excursion provided by http://vishub.org.")
              else
                myxml.langstring("Virtual Excursion provided by http://vishub.org.")
              end
            end
            if ejson["tags"] && ejson["tags"].kind_of?(Array)
              ejson["tags"].each do |tag|
                myxml.keyword do
                  myxml.langstring(tag.to_s)
                end
              end
            end
            #Add subjects as additional keywords
            if ejson["subject"]
              if ejson["subject"].kind_of?(Array)
                ejson["subject"].each do |subject|
                  myxml.keyword do
                    myxml.langstring(subject)
                  end 
                end
              elsif ejson["subject"].kind_of?(String)
                myxml.keyword do
                    myxml.langstring(ejson["subject"])
                end
              end
            end

            myxml.structure do
              myxml.source do
                myxml.langstring("LOMv1.0")
              end
              myxml.value do
                myxml.langstring("hierarchical")
              end
            end
            myxml.aggregationlevel do
              myxml.source do
                myxml.langstring("LOMv1.0")
              end
              myxml.value do
                myxml.langstring("4")
              end
            end
          end

          myxml.lifecycle do
            myxml.version do
              myxml.langstring("1.0")
            end
            myxml.status do
              myxml.source do
                myxml.langstring("LOMv1.0")
              end
              myxml.value do
                myxml.langstring("final")
              end
            end

            if (ejson["author"] and ejson["author"]["name"]) or (!excursion.nil? and !excursion.author.nil? and !excursion.author.name.nil?)
              myxml.contribute do
                myxml.role do
                  myxml.source do
                    myxml.langstring("LOMv1.0")
                  end
                  myxml.value do
                    myxml.langstring("author")
                  end
                end
                myxml.centity do
                  if ejson["author"] and ejson["author"]["name"]
                    myxml.vcard("begin:vcard\n n:"+ejson["author"]["name"]+"\n fn:\n end:vcard")
                  else
                    myxml.vcard("begin:vcard\n n:"+excursion.author.name+"\n fn:\n end:vcard")
                  end
                end
                myxml.date do
                  if excursion and !excursion.updated_at.nil?
                    myxml.datetime(excursion.updated_at.strftime("%d/%m/%y"))
                  else
                    myxml.datetime(Time.now.strftime("%d/%m/%y"))
                  end
                end
              end
            end
          end

          myxml.technical do
            myxml.format("text/html")
            if excursion and excursion.draft == false
              myxml.location("http://vishub.org/excursions/"+excursion.id.to_s)
            elsif ejson["vishMetadata"] and ejson["vishMetadata"]["id"] and (ejson["vishMetadata"]["draft"] == false or ejson["vishMetadata"]["draft"] == "false")
              myxml.location("http://vishub.org/excursions/"+ejson["vishMetadata"]["id"].to_s)
            end
            myxml.requirement do
              myxml.type do
                myxml.source do
                  myxml.langstring("LOMv1.0")
                end
                myxml.value do
                  myxml.langstring("browser")
                end
              end
              myxml.name do
                myxml.source do
                  myxml.langstring("LOMv1.0")
                end
                myxml.value do
                  myxml.langstring("any")
                end
              end
            end
            myxml.otherplatformrequirements do
              myxml.langstring("HTML5-compliant web browser")
            end
          end

          myxml.educational do
            myxml.interactivitytype do
              myxml.source do
                myxml.langstring("LOMv1.0")
              end
              myxml.value do
                myxml.langstring("mixed")
              end
            end
            myxml.learningresourcetype do
              myxml.source do
                myxml.langstring("LOMv1.0")
              end
              myxml.value do
                myxml.langstring("slide")
              end
            end
            myxml.interactivitylevel do
              myxml.source do
                myxml.langstring("LOMv1.0")
              end
              myxml.value do
                myxml.langstring("very high")
              end
            end
            myxml.intendedenduserrole do
              myxml.source do
                myxml.langstring("LOMv1.0")
              end
              myxml.value do
                myxml.langstring("learner")
              end
            end
            if ejson["context"]
              myxml.context do
                myxml.source do
                  myxml.langstring("LOMv1.0")
                end
                myxml.value do
                  myxml.langstring(readableContext(ejson["context"]))
                end
              end
            end
            if ejson["age_range"]
              myxml.typicalagerange do
                myxml.langstring(ejson["age_range"])
              end
            end
            if ejson["difficulty"]
              myxml.difficulty do
                myxml.source do
                  myxml.langstring("LOMv1.0")
                end
                myxml.value do
                  myxml.langstring(ejson["difficulty"])
                end
              end
            end
            if ejson["TLT"] or ejson["slides"]
              myxml.typicalLearningTime do
                if ejson["TLT"]
                  myxml.duration(ejson["TLT"])
                else
                  #Inferred
                  # 1 min per slide
                  # inferredTPL = (excursion.slide_count * 1).to_s
                  inferredTPL = (ejson["slides"].length * 1).to_s
                  myxml.duration("PT"+inferredTPL+"M0S")
                end
              end
            end
            if ejson["educational_objectives"]
              myxml.description do
                  myxml.langstring(ejson["educational_objectives"])
              end
            end
            if ejson["language"]
              myxml.language(ejson["language"])
            end
          end
        end
      end

      myxml.organizations('default'=>"ViSH",'structure'=>"hierarchical") do
        myxml.organization('identifier'=>"ViSH") do
          myxml.title("Virtual Science Hub")
          myxml.metadata() do
            myxml.schema("ADL SCORM")
            myxml.schemaversion("CAM 1.3")
            myxml.lom do
              myxml.general do
                myxml.identifier("ViSH")
                myxml.title do
                  myxml.langstring("Virtual Science Hub")
                end
                myxml.description do
                  myxml.langstring("Virtual Science Hub. http://vishub.org.")
                end
              end
            end
          end
          myxml.item('identifier'=>"VIRTUAL_EXCURSION_" + identifier,'identifierref'=>"VIRTUAL_EXCURSION_" + identifier + "_RESOURCE") do
            if ejson["title"]
              myxml.title(ejson["title"])
            else
              myxml.title("Untitled")
            end
          end
        end
      end

      myxml.resources do         
        myxml.resource('identifier'=>"VIRTUAL_EXCURSION_" + identifier + "_RESOURCE", 'type'=>"webcontent", 'href'=>"excursion.html", 'adlcp:scormtype'=>"sco") do
          myxml.file('href'=> "excursion.html")
        end
      end

    end    

    return myxml
  end

  def self.readableContext(context)
    case context
    when "unspecified"
      return "Unspecified"
    when "preschool"
      return "Preschool Education"
    when "pEducation"
      return "Primary Education"
    when "sEducation"
      return "Secondary Education"
    when "higher education"
      return "Higher Education"
    when "training"
      return "Professional Training"
    when "other"
      return "Other"
    else
      return context
    end
  end

  def to_scorm(controller)
    if self.scorm_needs_generate
      filePath = "#{Rails.root}/public/scorm/excursions/"
      fileName = self.id
      json = JSON(self.json)
      Excursion.createSCORM(filePath,fileName,json,self,controller)
      self.update_column(:scorm_timestamp, Time.now)
    end
  end

  def scorm_needs_generate
    if self.scorm_timestamp.nil? or self.updated_at > self.scorm_timestamp or !File.exist?("#{Rails.root}/public/scorm/excursions/#{self.id}.zip")
      return true
    else
      return false
    end
  end

  def remove_scorm
    if File.exist?("#{Rails.root}/public/scorm/excursions/#{self.id}.zip")
      File.delete("#{Rails.root}/public/scorm/excursions/#{self.id}.zip") 
    end
  end


  ####################
  ## PDF Management
  #################### 

  def to_pdf(controller)
    if self.pdf_needs_generate
      slidesQuantity = generate_thumbnails(controller)
      if slidesQuantity > 0
        pdfFolder = "#{Rails.root}/public/pdf/excursions/#{self.id}"

        #Generate PDF
        pdf = File.open(pdfFolder+"/#{self.id}.pdf", 'w')

        require 'RMagick'
        images = []
        slidesQuantity.times do |num|
          images.push(pdfFolder + "/#{self.id}_#{num+1}.png")
        end
        pdf_image_list = ::Magick::ImageList.new
        pdf_image_list.read(*images)
        pdf_image_list.write(pdfFolder + "/#{self.id}.pdf")
        pdf.close

        self.update_column(:pdf_timestamp, Time.now)
      end
    end
  end

  def generate_thumbnails(controller)
    begin
      #Create folder if not exists
      pdfFolder = "#{Rails.root}/public/pdf/excursions/#{self.id}"
      Dir.mkdir(pdfFolder) unless File.exists?(pdfFolder)

      require 'selenium-webdriver'
      Selenium::WebDriver::Chrome.path = "/usr/lib/chromium-browser/chromium-browser"
      driver = Selenium::WebDriver.for :chrome

      # Testing
      # excursion_url = 'http://vishub.org/excursions/55.full'
      
      excursion_url = controller.url_for( :controller => 'excursions', :action => 'show', :format => 'full', :id=>self.id)
      # driver.navigate.to excursion_url
      driver.get excursion_url

      #Specify screenshots dimensions
      width = 775
      height = 1042
      driver.execute_script %Q{ window.resizeTo(#{width}, #{height}); }

      #Hide fullscreen button
      driver.execute_script %Q{ $("#page-fullscreen").hide(); }
      #Disable non-iframe alerts
      driver.execute_script %Q{ window.alert = function(){}; }

      #Get slidesQuantity
      slidesQuantity = driver.execute_script %Q{ 
        return VISH.Slides.getSlidesQuantity();
      }

      #Take a screenshot of each slide
      slidesQuantity.times do |num|
        driver.execute_script %Q{
          VISH.Slides.goToSlide(#{num+1});
        }
        driver.execute_script %Q{ 
          $("article.current").css("display","block");
          $("article").not(".current").css("display","none");
        }

        Selenium::WebDriver::Wait.new(:timeout => 30).until { 
          # TODO:// VISH.SlideManager.isSlideLoaded()
          driver.execute_script("return true")
        }
        #Wait a constant period
        sleep 1.5

        #Remove alert (if is present)
        driver.switch_to.alert.accept rescue Selenium::WebDriver::Error::NoAlertOpenError

        driver.save_screenshot(pdfFolder + "/#{self.id}_#{num+1}.png")
      end

      driver.quit
      return slidesQuantity

    rescue Exception => e
      begin
        driver.quit
      rescue
      end
      puts e.message
      return -1
    end
  end

  def pdf_needs_generate
    if self.pdf_timestamp.nil? or self.updated_at > self.pdf_timestamp or !File.exist?("#{Rails.root}/public/pdf/excursions/#{self.id}/#{self.id}.pdf")
      return true
    else
      return false
    end
  end

  def remove_pdf
    if File.exist?("#{Rails.root}/public/pdf/excursions/#{self.id}")
      FileUtils.rm_rf("#{Rails.root}/public/pdf/excursions/#{self.id}") 
    end
  end

  ####################
  ## Evaluations
  #################### 

  def evaluations
    ExcursionEvaluation.where(:excursion_id => self.id)
  end

  def averageEvaluation
    evaluations_array = []
    if self.evaluations.length > 0
      6.times do |ind|
        evaluations_array.push(ExcursionEvaluation.average("answer_"+ind.to_s, :conditions=>["excursion_id=?", self.id]).to_f.round(2))
      end
    else
      evaluations_array = [0,0,0,0,0,0]
    end
    evaluations_array
  end

  def numberOfEvaluations
    ExcursionEvaluation.count("answer_1", :conditions=>["excursion_id=?", self.id])
  end

  def learningEvaluations
    ExcursionLearningEvaluation.where(:excursion_id => self.id)
  end

  def averageLearningEvaluation
    evaluations_array = []
    if self.learningEvaluations.length > 0
      6.times do |ind|
        evaluations_array.push(ExcursionLearningEvaluation.average("answer_"+ind.to_s, :conditions=>["excursion_id=?", self.id]).to_f.round(2))
      end
    else
      evaluations_array = [0,0,0,0,0,0]
    end
    evaluations_array
  end

  def numberOfLearningEvaluations
    ExcursionLearningEvaluation.count("answer_1", :conditions=>["excursion_id=?", self.id])
  end


  ####################
  ## Other Methods
  #################### 

  def clone_for sbj
    return nil if sbj.blank?
    e=Excursion.new
    e.author=sbj
    e.owner=sbj
    e.user_author=sbj.user.actor

    eJson = JSON(self.json)
    eJson["author"] = {name: sbj.name, vishMetadata:{ id: sbj.id}}
    if eJson["contributors"].nil?
      eJson["contributors"] = []
    end
    eJson["contributors"].push({name: self.author.name, vishMetadata:{ id: self.author.id}})
    e.json = eJson.to_json

    e.contributors=self.contributors.push(self.author)
    e.contributors.uniq!
    e.contributors.delete(sbj)
    e.draft=true
    e.save!
    e
  end

  #method used to return json objects to the recommendation in the last slide
  def reduced_json(controller)
      excursion_url = controller.excursion_url(:id => self.id)
      { :id => id,
        :url => excursion_url,
        :title => title,
        :author => author.name,
        :description => description,
        :image => thumbnail_url ? thumbnail_url : Site.current.config[:documents_hostname] + "assets/logos/original/excursion-00.png",
        :views => visit_count,
        :favourites => like_count,
        :number_of_slides => slide_count
      }
  end

  #we don't know what happens or how it happens but sometimes in social_stream
  # the activity inside the activity_object is nil, so we fix it here
  def fix_post_activity_nil      
    if self.post_activity == nil
      a = Activity.new :verb         => "post",
                       :author_id    => self.activity_object.author_id,
                       :user_author  => self.activity_object.user_author,
                       :owner        => self.activity_object.owner,
                       :relation_ids => self.activity_object.relation_ids,
                       :parent_id    => self.activity_object._activity_parent_id

      a.activity_objects << self.activity_object

      a.save!
    end
  end

  private

  def parse_for_meta
    parsed_json = JSON(json)

    activity_object.title = parsed_json["title"] ? parsed_json["title"] : "Title"
    activity_object.description = parsed_json["description"] 
    activity_object.tag_list = parsed_json["tags"]
    begin
      ageRange = parsed_json["age_range"]
      activity_object.age_min = ageRange.split("-")[0].delete(' ')
      activity_object.age_max = ageRange.split("-")[1].delete(' ')
    rescue
    end
    activity_object.save!

    if !parsed_json["vishMetadata"]
      parsed_json["vishMetadata"] = {}
    end
    parsed_json["vishMetadata"]["id"] = self.id.to_s
    parsed_json["vishMetadata"]["draft"] = self.draft.to_s

    parsed_json["author"] = {name: author.name, vishMetadata:{ id: author.id}}

    self.update_column :json, parsed_json.to_json
    self.update_column :excursion_type, parsed_json["type"]
    self.update_column :slide_count, parsed_json["slides"].size
    self.update_column :thumbnail_url, parsed_json["avatar"] ? parsed_json["avatar"] : Site.current.config[:documents_hostname] + "assets/logos/original/excursion-00.png"
  end

  def fix_relation_ids_drafts
    if self.draft
      activity_object.relation_ids=[Relation::Private.instance.id]
    else
      activity_object.relation_ids=[Relation::Public.instance.id]
    end
  end
  
end
