component output=false {
    function init(required string outputPath){variables.outputPath=arguments.outputPath;variables.accessPath=arguments.outputPath&".access/";if(!directoryExists(variables.accessPath))directoryCreate(variables.accessPath,true);return this;}

    void function register(required string filename, required string subsection){
        var name=getFileFromPath(arguments.filename);
        if(!len(name))return;
        fileWrite(variables.accessPath&name&".json",serializeJson({subsection:arguments.subsection,created_at:dateTimeFormat(now(),"yyyy-mm-dd'T'HH:nn:ss")}),"utf-8");
    }

    string function subsection(required string filename){
        var marker=variables.accessPath&getFileFromPath(arguments.filename)&".json";
        if(!fileExists(marker))return "";
        try{return deserializeJson(fileRead(marker,"utf-8")).subsection ?: "";}catch(any e){return "";}
    }

    string function resolve(required string filename){
        var safe=getFileFromPath(arguments.filename);
        if(safe!=arguments.filename)return "";
        var path=variables.outputPath&safe;
        return fileExists(path)?path:"";
    }

    // Metadata for every registered output (name, module, created, size), newest first.
    array function listAll(){
        var out=[];
        if(!directoryExists(variables.accessPath))return out;
        var markers=directoryList(variables.accessPath,false,"query","*.json");
        for(var row in markers){
            var name=left(row.name,len(row.name)-5);var filePath=variables.outputPath&name;
            var meta={};try{meta=deserializeJson(fileRead(variables.accessPath&row.name,"utf-8"));}catch(any e){meta={};}
            arrayAppend(out,{filename:name,subsection:meta.subsection?:"",created_at:meta.created_at?:"",exists:fileExists(filePath),size:fileExists(filePath)?getFileInfo(filePath).size:0});
        }
        arraySort(out,function(a,b){return compare(b.created_at&"",a.created_at&"");});
        return out;
    }

    void function cleanOld(numeric hours=48){
        var cutoff=dateAdd("h",-arguments.hours,now());
        var q=directoryList(variables.outputPath,false,"query");
        for(var row in q){
            if(row.type=="File" && row.dateLastModified<cutoff){
                try{fileDelete(variables.outputPath&row.name);}catch(any ignored){}
                var marker=variables.accessPath&row.name&".json";
                if(fileExists(marker))try{fileDelete(marker);}catch(any ignored2){}
            }
        }
    }
}
