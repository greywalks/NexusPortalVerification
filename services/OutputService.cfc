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
