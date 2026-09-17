component extends="services.AuthService" output=false {
    function init(required string datasource) {
        variables.datasource = arguments.datasource;
        super.init();
        return this;
    }
}
