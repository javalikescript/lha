define(['./web-chat.xml', './web-chat.css'], function(pageXml, pageCss) {

  appendStyle(pageCss, 'web-chat');

  var API_PATH = '/llm';

  var vue = new Vue({
    template: pageXml,
    data: {
      models: [],
      model: '',
      messages: [],
      userInput: '',
      loading: false,
      temperature: 0.7,
      top_p: 0.9,
      top_k: 40,
      max_tokens: 512
    },
    methods: {
      onShow: function() {
        return fetch(API_PATH + '/models', {
          headers: {"Accept": 'application/json'}
        }).then(rejectIfNotOk).then(getResponseJson).then(function(response) {
          if (response.data.length > 0) {
            this.model = response.data[0].id;
          }
          this.models = response.data;
        }.bind(this), function(error) {
          console.error('Error:', error);
          toaster.toast('Cannot fetch models');
        });
      },
      sendMessage: function() {
        if (!(this.userInput.trim() && this.model && this.model.trim())) {
          return;
        }
        this.loading = true;
        this.messages.push({
          role: 'user',
          content: this.userInput
        });
        var userMessage = this.userInput;
        this.userInput = '';
        if (userMessage.trim().toLowerCase() === 'hi') {
          this.messages.push({
            role: 'assistant',
            content: userMessage
          });
          self.loading = false;
          return;
        }
        var payload = {
          messages: this.messages,
          model: this.model,
          temperature: this.temperature,
          top_p: this.top_p,
          top_k: this.top_k,
          max_tokens: this.max_tokens,
          stream: false
        };
        var self = this;
        return fetch(API_PATH + '/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(payload)
        }).then(rejectIfNotOk).then(getResponseJson).then(function(data) {
          if (data.choices && data.choices.length > 0) {
            var assistantMessage = data.choices[0].message.content;
            self.messages.push({
              role: 'assistant',
              content: assistantMessage
            });
          } else {
            console.error('No choices in response:', data);
            toaster.toast('No response');
          }
        }).catch(function(error) {
          console.error('Error:', error);
          toaster.toast('Error: ' + error.message);
          self.messages.pop();
        }).finally(function() {
          self.loading = false;
          self.$nextTick(function() {
            var container = self.$refs.messagesContainer;
            if (container) {
              container.scrollTop = container.scrollHeight;
            }
          });
        });
      },
      clearHistory: function() {
        return confirmation.ask('Are you sure you want to clear the chat history?').then(function() {
          this.messages = [];
        }.bind(this));
      }
    }
  });

  addPageComponent(vue, 'comments', true);

});
