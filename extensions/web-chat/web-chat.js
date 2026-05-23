define(['./web-chat.xml', './web-chat.css', 'engine/configuration/extensions/web-chat/'], function(pageXml, pageCss, config) {

  appendStyle(pageCss, 'web-chat');

  console.log('config', config);
  var API_PATH = config.value.href || '/llm';
  var API_KEY = config.value.key ? 'Bearer ' + config.value.key : undefined;

  var TOOLS = [{
    type: "function",
    function: {
      name: "get_things_descriptions",
      description: "List all the things their IDs and descriptions"
    }
  }, {
    type: "function",
    function: {
      name: "get_thing_properties",
      description: "Retrieve properties of a specific thing",
      parameters: {
        type: "object",
        properties: {
          thing_id: {
            type: "string",
            description: "The ID of the thing to get properties for"
          }
        },
        required: ["thing_id"]
      }
    }
  }]

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
          headers: {
            "Accept": "application/json",
            "Authorization": API_KEY,
          }
        }).then(rejectIfNotOk).then(getResponseJson).then(function(response) {
          if (response.data.length > 0) {
            this.model = response.data[0].id;
          }
          this.models = response.data;
          this.messages.push({
            role: 'system',
            content: 'Your are an helpful assistant for home automation. Use tools to list and interact with the things.'
          });
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
        this.sendMessages();
      },
      sendMessages: function() {
        var payload = {
          messages: this.messages,
          model: this.model,
          temperature: this.temperature,
          top_p: this.top_p,
          top_k: this.top_k,
          max_tokens: this.max_tokens,
          stream: false,
          tools: TOOLS,
          tool_choice: "auto"
        };
        var self = this;
        return fetch(API_PATH + '/chat/completions', {
          method: 'POST',
          headers: {
            "Accept": "application/json",
            "Authorization": API_KEY,
            "Content-Type": "application/json"
          },
          body: JSON.stringify(payload)
        }).then(rejectIfNotOk).then(getResponseJson).then(function(data) {
          if (data.choices && data.choices.length > 0) {
            var message = data.choices[0].message;
            self.messages.push(message);
            if (message.tool_calls) {
              var promises = [];
              message.tool_calls.forEach(function(toolCall) {
                var args = toolCall.function.arguments && JSON.parse(toolCall.function.arguments);
                if (toolCall.function.name === 'get_things_descriptions') {
                  promises.push(app.getThings().then(function(things) {
                    return {
                      tool_call_id: toolCall.id,
                      role: 'tool',
                      content: JSON.stringify(things)
                    };
                  }));
                } else if (toolCall.function.name === 'get_thing_properties') {
                  promises.push(fetch('/engine/properties/' + args.thing_id).then(rejectIfNotOk).then(getResponseJson).then(function(properties) {
                    return {
                      tool_call_id: toolCall.id,
                      role: 'tool',
                      content: JSON.stringify(properties)
                    };
                  }).catch(function(error) {
                    return {
                      tool_call_id: toolCall.id,
                      role: 'tool',
                      content: 'Error fetching properties: ' + error.message
                    };
                  }));
                }
              });
              if (promises.length > 0) {
                Promise.all(promises).then(function(results) {
                  self.messages.push(...results);
                  self.sendMessages();
                });
              }
            }
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
