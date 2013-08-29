"use strict";
/*
ngTable: Table + Angular JS

@author Vitalii Savchuk <esvit666@gmail.com>
@copyright 2013 Vitalii Savchuk <esvit666@gmail.com>
@version 0.2.1
@url https://github.com/esvit/ng-table/
@license New BSD License <http://creativecommons.org/licenses/BSD/>
*/

angular.module("ngTable", []).directive("ngTable", [
  "$compile", "$q", "$parse", "$http", "ngTableOptions", function($compile, $q, $parse, $http, ngTableOptions) {
    return {
      restrict: "A",
      priority: 1001,
      scope: {
        options: "=ngTable",
        showFilter: "=?"
      },
      controller: [
        "$scope", "$timeout", function(s, $timeout) {
          var updateOptions;
          s.options = s.options || new ngTableOptions({
            page: 1,
            count: 10
          });
          s.$watch('options.filter', (function(value) {
            if (s.options.$liveFiltering && s.options.paginationEnabled) {
              return s.goToPage(1);
            }
          }), true);
          updateOptions = function(newOptions) {
            return _.extend(s.options, newOptions);
          };
          s.goToPage = function(page) {
            if (page > 0 && s.options.page !== page && s.options.count * (page - 1) <= s.options.total) {
              return updateOptions({
                page: page
              });
            }
          };
          s.changeCount = function(count) {
            return updateOptions({
              page: 1,
              count: count
            });
          };
          s.doFilter = function() {
            return updateOptions({
              page: 1
            });
          };
          return s.sortBy = function(column) {
            var sorting, sortingOptions;
            if (!column.sortable) {
              return;
            }
            sorting = s.options.sorting && s.options.sorting[column.sortable] && (s.options.sorting[column.sortable] === "desc");
            sortingOptions = {};
            sortingOptions[column.sortable] = (sorting ? "asc" : "desc");
            return updateOptions({
              sorting: sortingOptions
            });
          };
        }
      ],
      compile: function(element, attrs) {
        var columns, i;
        i = 0;
        columns = [];
        _.forEach(element.find("tr").eq(0).find("td"), function(item) {
          var el, filter, filterTemplateURL, headerTemplateURL, parsedTitle;
          el = $(item);
          if (el.attr("ignore-cell") && "true" === el.attr("ignore-cell")) {
            return;
          }
          parsedTitle = function(scope) {
            return $parse(el.attr("data-title"))(scope) || el.attr("data-title") || " ";
          };
          el.attr('data-title-text', parsedTitle());
          headerTemplateURL = el.attr("header") ? $parse(el.attr("header"))() : false;
          filter = el.attr("filter") ? $parse(el.attr("filter"))() : false;
          filterTemplateURL = false;
          if (filter && filter.templateURL) {
            filterTemplateURL = filter.templateURL;
            delete filter.templateURL;
          }
          return columns.push({
            id: i++,
            title: parsedTitle,
            sortable: (el.attr("data-sortable") ? el.attr("data-sortable") : false),
            filter: filter,
            filterTemplateURL: filterTemplateURL,
            headerTemplateURL: headerTemplateURL,
            filterData: (el.attr("filter-data") ? el.attr("filter-data") : null),
            show: (el.attr("ng-show") ? function(scope) {
              return $parse(el.attr("ng-show"))(scope);
            } : function() {
              return true;
            })
          });
        });
        return function(scope, element, attrs) {
          var generatePages, headerTemplate, paginationTemplate, tbody;
          scope.columns = columns;
          generatePages = function(currentPage, totalItems, pageSize) {
            var maxBlocks, maxPage, maxPivotPages, minPage, numPages, pages;
            maxBlocks = 11;
            pages = [];
            numPages = Math.ceil(totalItems / pageSize);
            if (numPages > 1) {
              pages.push({
                type: "prev",
                number: Math.max(1, currentPage - 1),
                active: currentPage > 1
              });
              pages.push({
                type: "first",
                number: 1,
                active: currentPage > 1
              });
              maxPivotPages = Math.round((maxBlocks - 5) / 2);
              minPage = Math.max(2, currentPage - maxPivotPages);
              maxPage = Math.min(numPages - 1, currentPage + maxPivotPages * 2 - (currentPage - minPage));
              minPage = Math.max(2, minPage - (maxPivotPages * 2 - (maxPage - minPage)));
              i = minPage;
              while (i <= maxPage) {
                if ((i === minPage && i !== 2) || (i === maxPage && i !== numPages - 1)) {
                  pages.push({
                    type: "more"
                  });
                } else {
                  pages.push({
                    type: "page",
                    number: i,
                    active: currentPage !== i
                  });
                }
                i++;
              }
              pages.push({
                type: "last",
                number: numPages,
                active: currentPage !== numPages
              });
              pages.push({
                type: "next",
                number: Math.min(numPages, currentPage + 1),
                active: currentPage < numPages
              });
            }
            return pages;
          };
          scope.$watch('options', function(options) {
            if (_.isUndefined(options)) {
              return;
            }
            return scope.pages = generatePages(options.page, options.total, options.count);
          }, true);
          scope.parse = function(text) {
            return text(scope);
          };
          _.forEach(columns, function(column) {
            var promise;
            if (!column.filterData) {
              return;
            }
            promise = $parse(column.filterData)(scope, {
              $column: column
            });
            if (!(_.isObject(promise) && _.isFunction(promise.then))) {
              throw new Error("Function " + column.filterData + " must be promise");
            }
            delete column["filterData"];
            return promise.then(function(data) {
              if (!_.isArray(data)) {
                data = [];
              }
              data.unshift({
                title: "-",
                id: ""
              });
              return column.data = data;
            });
          });
          if (!element.hasClass("ng-table")) {
            scope.templates = {
              header: (attrs.templateHeader ? attrs.templateHeader : "ng-table/header.html"),
              pagination: (attrs.templatePagination ? attrs.templatePagination : "ng-table/pager.html")
            };
            headerTemplate = '<thead>\n<tr><th ng-class="{sortable: column.sortable,\'sort-asc\': options.sorting[column.sortable]==\'asc\', \'sort-desc\': options.sorting[column.sortable]==\'desc\'}" ng-click="sortBy(column)" ng-repeat="column in columns" ng-show="column.show(this)" data-column="{{parse(column.title)}}" class="header"><div ng-hide="column.headerTemplateURL" ng-bind="parse(column.title)"></div><div ng-show="column.headerTemplateURL" ng-include="column.headerTemplateURL"></div></th></tr><tr ng-show="showFilter" class="ng-table-filters"><th ng-repeat="column in columns" ng-show="column.show(this)" data-title-text="{{parse(column.title)}}" class="filter"><form ng-submit="doFilter()"><input type="submit" tabindex="-1" style="position: absolute; left: -9999px; width: 1px; height: 1px;"/><div ng-repeat="(name, filter) in column.filter"><div ng-if="column.filterTemplateURL"><div ng-include="column.filterTemplateURL"></div></div><div ng-if="!column.filterTemplateURL"><div ng-include="\'ng-table/filters/\' + filter + \'.html\'"></div></div></div></form></th></tr>\n</thead>';
            headerTemplate = $compile(headerTemplate)(scope);
            element.filter("thead").remove();
            tbody = element.find('tbody');
            if (tbody[0]) {
              $(tbody[0]).before(headerTemplate);
            } else {
              element.prepend(headerTemplate);
            }
            element.addClass("ng-table");
            if (scope.options.paginationEnabled) {
              paginationTemplate = '<div class="pagination ng-cloak"><ul class="pagination"><li ng-class="{\'disabled\': !page.active}" ng-repeat="page in pages" ng-switch="page.type"><a ng-switch-when="prev" ng-click="goToPage(page.number)" href="">«</a><a ng-switch-when="first" ng-click="goToPage(page.number)" href="">{{page.number}}</a><a ng-switch-when="page" ng-click="goToPage(page.number)" href="">{{page.number}}</a><a ng-switch-when="more" ng-click="goToPage(page.number)" href="">…</a><a ng-switch-when="last" ng-click="goToPage(page.number)" href="">{{page.number}}</a><a ng-switch-when="next" ng-click="goToPage(page.number)" href="">»</a></li></ul><div ng-show="params.counts.length" class="btn-group pull-right"><button ng-repeat="count in params.counts" type="button" ng-class="{\'active\':params.count==count}" ng-click="changeCount(count)" class="btn btn-mini">{{count}}</button></div></div>';
              paginationTemplate = $compile(paginationTemplate)(scope);
              return element.after(paginationTemplate);
            }
          }
        };
      }
    };
  }
]);

/*
//@ sourceMappingURL=directive.js.map
*/
var __hasProp = {}.hasOwnProperty;

angular.module("ngTable").factory("ngTableOptions", function() {
  var ngTableOptions;
  ngTableOptions = function(data) {
    var ignoreFields;
    ignoreFields = ["total", "counts", "$liveFiltering"];
    this.page = 1;
    this.count = 1;
    this.counts = [10, 25, 50, 100];
    this.filter = {};
    this.sorting = {};
    this.paginationEnabled = true;
    _.extend(this, data);
    this.orderBy = function() {
      var column, direction, sorting, _ref;
      sorting = [];
      _ref = this.sorting;
      for (column in _ref) {
        if (!__hasProp.call(_ref, column)) continue;
        direction = _ref[column];
        sorting.push((direction === "asc" ? "+" : "-") + column);
      }
      return sorting;
    };
    this.url = function(asString) {
      var item, key, name, pairs, pname, subkey;
      asString = asString || false;
      pairs = (asString ? [] : {});
      for (key in this) {
        if (_.has(this, key)) {
          if (ignoreFields.indexOf(key) >= 0) {
            continue;
          }
          item = this[key];
          name = encodeURIComponent(key);
          if (typeof item === "object") {
            for (subkey in item) {
              if (!_.isUndefined(item[subkey]) && item[subkey] !== "") {
                pname = name + "[" + encodeURIComponent(subkey) + "]";
                if (asString) {
                  pairs.push(pname + "=" + encodeURIComponent(item[subkey]));
                } else {
                  pairs[pname] = encodeURIComponent(item[subkey]);
                }
              }
            }
          } else if (!_.isFunction(item) && !_.isUndefined(item) && item !== "") {
            if (asString) {
              pairs.push(name + "=" + encodeURIComponent(item));
            } else {
              pairs[name] = encodeURIComponent(item);
            }
          }
        }
      }
      return pairs;
    };
    return this;
  };
  return ngTableOptions;
});

/*
//@ sourceMappingURL=options.js.map
*/