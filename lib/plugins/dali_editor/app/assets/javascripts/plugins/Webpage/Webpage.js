Dali.Plugins["Webpage"] = function (base){
    return {
        getConfig: function () {
            return {
                name: 'Webpage',
                category: 'multimedia',
                needsConfigModal: false,
                needsTextEdition: false,
                icon: 'fa-globe'
            };
        },
        getToolbar: function () {
            return [
                {
                    name: 'url',
                    humanName: 'URL',
                    type: 'text',
                    tab: 'Main',
                    accordion: 'Basic',
                    autoManaged: false,
                    value: 'http://www.adams.es/'

                },
                {
                    name: 'opacity',
                    humanName: 'Opacity',
                    type: 'number',
                    value: 1,
                    min: 0,
                    max: 1,
                    step: 0.1,
                    tab: 'Main',
                    accordion: 'Box'
                },
                {
                    name: 'borderSize',
                    humanName: 'Border Size',
                    type: 'number',
                    value: 0,
                    min: 0,
                    max: 10,
                    autoManaged: false,
                    tab: 'Main',
                    accordion: 'Box'
                },
                {
                    name: 'test',
                    humanName: 'Test',
                    type: 'text',
                    isAttribute: true,
                    tab: 'Other',
                    accordion: 'Extra'
                }
            ]
        },
        getSections: function () {
            return [
                {
                    tab: 'Main',
                    accordion: ['Basic', 'Box']
                },
                {
                    tab: 'Other',
                    accordion: ['Extra']
                },

            ];
        },
        getInitialState: function () {
            return {url: 'http://www.adams.es/', borderSize: 0, thumbnailVisibility: 'hidden'};
        },
        getConfigTemplate: function (state) {
            return "<div> Url: <input type=\"text\" autofocus id=\"BasicImage_input\" value=\"" + state.url + "\"><br><button onclick=\"$dali$.showPreview()\">Show preview</button><iframe width=\"560\" height=\"315\"id=\"BasicImage_preview\" frameborder=\"0\" allowfullscreen src=\"" + state.url + "\" style=\"width: 180px; height: auto; visibility: " + state.thumbnailVisibility + ";\"></iframe></div>";
        },
        getRenderTemplate: function (state) {
            return "<iframe width=\"560\" height=\"315\" style=\"width: 100%; height: 100%; pointer-events: none; border: solid " + state.borderSize + "px green; z-index:0;\" src=\"" + state.url + "\"></iframe>"
        },
        handleToolbar: function (name, value) {
            base.setState(name, value);
        },
        showPreview: function () {
            var vid = $('#BasicImage_preview');
            var input = $('#BasicImage_input');
            //base.setState('url', input.val());
            base.setState('thumbnailVisibility', 'visible');
            // vid.attr('src', input.val());
            vid.css('visibility', 'visible');
        }
    }
}