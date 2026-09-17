component output=false {
    function init(required string datasource, required any excelService){
        variables.datasource=arguments.datasource;
        variables.excel=arguments.excelService;
        return this;
    }

    struct function importSpreadsheet(required string path){
        var rows=variables.excel.readFirstSheet(arguments.path,6);
        var result={rows:0,courses_created:0,courses_matched:0,topics_created:0,sessions_created:0,videos_created:0,skipped:0,errors:[]};
        for(var i=1;i<=arrayLen(rows);i++){
            var source=rows[i];
            var hasData=false;for(var sourceKey in source)if(len(trim(source[sourceKey]&""))){hasData=true;break;}
            if(!hasData)continue;
            result.rows++;
            var courseDate=normalizeDate(valueFor(source,["Course Date*","Course Date","Date","Training Date"]));
            var courseTitle=trim(valueFor(source,["Course Title*","Course Title","Course","Training"]));
            if(!len(courseDate)||!len(courseTitle)){
                result.skipped++;
                arrayAppend(result.errors,"Row "&(i+6)&": Course Date and Course Title are required.");
                continue;
            }
            var preVideoUrl=trim(valueFor(source,["Video URL","URL"]));
            if(len(preVideoUrl)&&!reFindNoCase("^https?://",preVideoUrl)){
                result.skipped++;
                arrayAppend(result.errors,"Row "&(i+6)&": Video URL must begin with http:// or https://.");
                continue;
            }
            try{
                transaction {
                    var course=findCourse(courseDate,courseTitle);
                    var courseId=0;
                    if(structCount(course)){
                        courseId=course.id;
                        result.courses_matched++;
                    }else{
                        courseId=createCourse(courseDate,courseTitle,valueFor(source,["Notes","Course Notes"]));
                        result.courses_created++;
                    }

                    var topicTitle=trim(valueFor(source,["Topic","Topic Title"]));
                    var lessonPlan=trim(valueFor(source,["Lesson Plan","Description"]));
                    var keyPoints=trim(valueFor(source,["Key Points","Key Points / Objectives","Objectives"]));
                    var videoUrl=trim(valueFor(source,["Video URL","URL"]));
                    var videoTitle=trim(valueFor(source,["Video Title","Video"]));
                    var topicId=0;
                    if(len(topicTitle)||len(lessonPlan)||len(keyPoints)||len(videoUrl)){
                        if(!len(topicTitle))topicTitle="Course resources";
                        topicId=findOrCreateTopic(courseId,topicTitle,lessonPlan,keyPoints);
                        if(topicId.created)result.topics_created++;
                        if(len(videoUrl)){
                            if(!reFindNoCase("^https?://",videoUrl))throw(type="USSI.TrainingImport",message="Video URL must begin with http:// or https://.");
                            var existingVideo=queryExecute("SELECT id FROM training_videos WHERE topic_id=:topic AND url=:url",{topic:topicId.id,url:videoUrl},{datasource:variables.datasource});
                            if(!existingVideo.recordCount){
                                queryExecute("INSERT INTO training_videos(topic_id,title,url) VALUES(:topic,:title,:url)",{topic:topicId.id,title:len(videoTitle)?videoTitle:videoUrl,url:videoUrl},{datasource:variables.datasource});
                                result.videos_created++;
                            }
                        }
                    }

                    var trainer=trim(valueFor(source,["Trainer","Trainer Name","Instructor"]));
                    var location=trim(valueFor(source,["Location","Training Location"]));
                    if(len(trainer)||len(location)){
                        if(!len(trainer))trainer="Unassigned";
                        var existingSession=queryExecute("SELECT id FROM training_sessions WHERE week_id=:course AND session_date=:date AND trainer_name=:trainer AND COALESCE(location,'')=:location",{course:courseId,date:courseDate,trainer:trainer,location:location},{datasource:variables.datasource});
                        if(!existingSession.recordCount){
                            queryExecute("INSERT INTO training_sessions(week_id,trainer_name,session_date,location) VALUES(:course,:trainer,:date,:location)",{course:courseId,trainer:trainer,date:courseDate,location:{value:location,null:!len(location)}},{datasource:variables.datasource});
                            result.sessions_created++;
                        }
                    }
                }
            }catch(any e){
                result.skipped++;
                arrayAppend(result.errors,"Row "&(i+6)&": "&(e.message?:"Could not import this row."));
            }
        }
        return result;
    }

    private struct function findCourse(required string courseDate,required string title){
        var q=queryExecute("SELECT id,title,start_date FROM training_weeks WHERE start_date=:date AND LOWER(title)=LOWER(:title)",{date:arguments.courseDate,title:arguments.title},{datasource:variables.datasource});
        return q.recordCount?{id:q.id[1],title:q.title[1],start_date:q.start_date[1]}:{};
    }

    private numeric function createCourse(required string courseDate,required string title,string notes=""){
        var nextNumber=queryExecute("SELECT COALESCE(MAX(week_number),0)+1 n FROM training_weeks",{}, {datasource:variables.datasource}).n[1];
        var created={};
        queryExecute("INSERT INTO training_weeks(week_number,title,start_date,notes) VALUES(:number,:title,:date,:notes)",{number:nextNumber,title:arguments.title,date:arguments.courseDate,notes:arguments.notes},{datasource:variables.datasource,result:"created"});
        if(structKeyExists(created,"generatedKey")&&val(created.generatedKey))return val(created.generatedKey);
        return val(queryExecute("SELECT MAX(id) id FROM training_weeks",{}, {datasource:variables.datasource}).id[1]);
    }

    private struct function findOrCreateTopic(required numeric courseId,required string title,string lessonPlan="",string keyPoints=""){
        var q=queryExecute("SELECT id FROM training_topics WHERE week_id=:course AND LOWER(title)=LOWER(:title)",{course:arguments.courseId,title:arguments.title},{datasource:variables.datasource});
        if(q.recordCount)return{id:q.id[1],created:false};
        var sortOrder=queryExecute("SELECT COALESCE(MAX(sort_order),0)+1 n FROM training_topics WHERE week_id=:course",{course:arguments.courseId},{datasource:variables.datasource}).n[1];
        var created={};
        queryExecute("INSERT INTO training_topics(week_id,title,lesson_plan,key_points,sort_order) VALUES(:course,:title,:lesson,:points,:sort)",{course:arguments.courseId,title:arguments.title,lesson:arguments.lessonPlan,points:arguments.keyPoints,sort:sortOrder},{datasource:variables.datasource,result:"created"});
        var id=structKeyExists(created,"generatedKey")?val(created.generatedKey):val(queryExecute("SELECT MAX(id) id FROM training_topics",{}, {datasource:variables.datasource}).id[1]);
        return{id:id,created:true};
    }

    private string function valueFor(required struct row,required array aliases){
        for(var key in arguments.row){
            var normalized=reReplace(lCase(key),"[^a-z0-9]","","all");
            for(var alias in arguments.aliases)if(normalized==reReplace(lCase(alias),"[^a-z0-9]","","all"))return arguments.row[key]&"";
        }
        return "";
    }

    private string function normalizeDate(any value=""){
        if(isDate(arguments.value))return dateFormat(arguments.value,"yyyy-mm-dd");
        var raw=trim(arguments.value&"");
        if(!len(raw))return "";
        try{return dateFormat(parseDateTime(raw),"yyyy-mm-dd");}catch(any ignored){return "";}
    }
}
