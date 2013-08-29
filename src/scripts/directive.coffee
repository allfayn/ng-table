"use strict"

###
ngTable: Table + Angular JS

@author Vitalii Savchuk <esvit666@gmail.com>
@copyright 2013 Vitalii Savchuk <esvit666@gmail.com>
@version 0.2.1
@url https://github.com/esvit/ng-table/
@license New BSD License <http://creativecommons.org/licenses/BSD/>
###

angular.module("ngTable", []).directive("ngTable", ["$compile", "$q", "$parse", "$http", "ngTableOptions", ($compile, $q, $parse, $http, ngTableOptions) ->
  restrict: "A"
  priority: 1001
  scope:
    options:"=ngTable"
    showFilter:"=?"
  controller: [ "$scope", "$timeout", (s, $timeout) ->
    # initialize with user provided options or reasonable defaults
    s.options = s.options or new ngTableOptions({page: 1, count: 10})

    # update result every time filter changes
    s.$watch('options.filter', ((value) ->
      if s.options.$liveFiltering and s.options.paginationEnabled
        s.goToPage 1
    ), true)

    updateOptions = (newOptions) ->
      _.extend(s.options, newOptions)

    # goto page
    s.goToPage = (page) ->
      updateOptions page: page  if page > 0 and s.options.page isnt page and s.options.count * (page - 1) <= s.options.total

    # change items per page
    s.changeCount = (count) ->
      updateOptions
        page: 1
        count: count


    s.doFilter = ->
      updateOptions page: 1

    s.sortBy = (column) ->
      return  unless column.sortable
      sorting = s.options.sorting and s.options.sorting[column.sortable] and (s.options.sorting[column.sortable] is "desc")
      sortingOptions = {}
      sortingOptions[column.sortable] = (if sorting then "asc" else "desc")
      updateOptions sorting: sortingOptions
  ]
  compile: (element, attrs) ->
    i = 0
    columns = []
    _.forEach element.find("tr").eq(0).find("td"), (item) ->
      el = $(item)
      if (el.attr("ignore-cell") && "true" == el.attr("ignore-cell"))
        return
      parsedTitle = (scope) -> $parse(el.attr("data-title"))(scope) or el.attr("data-title") or " "
      el.attr('data-title-text', parsedTitle())

      headerTemplateURL = if el.attr("header") then $parse(el.attr("header"))() else false

      filter = if el.attr("filter") then $parse(el.attr("filter"))() else false
      filterTemplateURL = false
      if filter && filter.templateURL
          filterTemplateURL = filter.templateURL
          delete filter.templateURL

      columns.push
        id: i++
        title: parsedTitle
        sortable: (if el.attr("data-sortable") then el.attr("data-sortable") else false)
        filter: filter
        filterTemplateURL: filterTemplateURL
        headerTemplateURL: headerTemplateURL
        filterData: (if el.attr("filter-data") then el.attr("filter-data") else null)
        show: (if el.attr("ng-show") then (scope) -> $parse(el.attr("ng-show"))(scope) else () -> true)


    (scope, element, attrs) ->
      scope.columns = columns
      # generate array of pages
      generatePages = (currentPage, totalItems, pageSize) ->
        maxBlocks = 11
        pages = []
        numPages = Math.ceil(totalItems / pageSize)
        if numPages > 1
          pages.push
            type: "prev"
            number: Math.max(1, currentPage - 1)
            active: currentPage > 1

          pages.push
            type: "first"
            number: 1
            active: currentPage > 1

          maxPivotPages = Math.round((maxBlocks - 5) / 2)
          minPage = Math.max(2, currentPage - maxPivotPages)
          maxPage = Math.min(numPages - 1, currentPage + maxPivotPages * 2 - (currentPage - minPage))
          minPage = Math.max(2, minPage - (maxPivotPages * 2 - (maxPage - minPage)))
          i = minPage

          while i <= maxPage
            if (i is minPage and i isnt 2) or (i is maxPage and i isnt numPages - 1)
              pages.push type: "more"
            else
              pages.push
                type: "page"
                number: i
                active: currentPage isnt i

            i++
          pages.push
            type: "last"
            number: numPages
            active: currentPage isnt numPages

          pages.push
            type: "next"
            number: Math.min(numPages, currentPage + 1)
            active: currentPage < numPages

        pages

      scope.$watch 'options', (options) ->
        return  if _.isUndefined(options)
        scope.pages = generatePages(options.page, options.total, options.count)
      , true

      scope.parse = (text) ->
        return text(scope)

      # get data from columns
      _.forEach columns, (column) ->
        return  unless column.filterData
        promise = $parse(column.filterData)(scope, $column: column)
        throw new Error("Function " + column.filterData + " must be promise")  unless (_.isObject(promise) && _.isFunction(promise.then))
        delete column["filterData"]

        promise.then (data) ->
          data = []  unless _.isArray(data)
          data.unshift title: "-", id: ""
          column.data = data

      # create table
      unless element.hasClass("ng-table")
        scope.templates =
          header: (if attrs.templateHeader then attrs.templateHeader else "ng-table/header.html")
          pagination: (if attrs.templatePagination then attrs.templatePagination else "ng-table/pager.html")

        # workaround for angular 1.2 issue with ng-include
        headerTemplate = '''
        <thead>
        <tr><th ng-class="{sortable: column.sortable,\'sort-asc\': options.sorting[column.sortable]==\'asc\', \'sort-desc\': options.sorting[column.sortable]==\'desc\'}" ng-click="sortBy(column)" ng-repeat="column in columns" ng-show="column.show(this)" data-column="{{parse(column.title)}}" class="header"><div ng-hide="column.headerTemplateURL" ng-bind="parse(column.title)"></div><div ng-show="column.headerTemplateURL" ng-include="column.headerTemplateURL"></div></th></tr><tr ng-show="showFilter" class="ng-table-filters"><th ng-repeat="column in columns" ng-show="column.show(this)" data-title-text="{{parse(column.title)}}" class="filter"><form ng-submit="doFilter()"><input type="submit" tabindex="-1" style="position: absolute; left: -9999px; width: 1px; height: 1px;"/><div ng-repeat="(name, filter) in column.filter"><div ng-if="column.filterTemplateURL"><div ng-include="column.filterTemplateURL"></div></div><div ng-if="!column.filterTemplateURL"><div ng-include="\'ng-table/filters/\' + filter + \'.html\'"></div></div></div></form></th></tr>
        </thead>
        '''
        headerTemplate = $compile(headerTemplate)(scope)
        element.filter("thead").remove()
        tbody = element.find('tbody')
        if (tbody[0]) then $(tbody[0]).before headerTemplate else element.prepend headerTemplate
        element.addClass "ng-table"

        if scope.options.paginationEnabled
          paginationTemplate = '''
            <div class="pagination ng-cloak"><ul class="pagination"><li ng-class="{\'disabled\': !page.active}" ng-repeat="page in pages" ng-switch="page.type"><a ng-switch-when="prev" ng-click="goToPage(page.number)" href="">«</a><a ng-switch-when="first" ng-click="goToPage(page.number)" href="">{{page.number}}</a><a ng-switch-when="page" ng-click="goToPage(page.number)" href="">{{page.number}}</a><a ng-switch-when="more" ng-click="goToPage(page.number)" href="">…</a><a ng-switch-when="last" ng-click="goToPage(page.number)" href="">{{page.number}}</a><a ng-switch-when="next" ng-click="goToPage(page.number)" href="">»</a></li></ul><div ng-show="params.counts.length" class="btn-group pull-right"><button ng-repeat="count in params.counts" type="button" ng-class="{\'active\':params.count==count}" ng-click="changeCount(count)" class="btn btn-mini">{{count}}</button></div></div>
          '''
          paginationTemplate = $compile(paginationTemplate)(scope)
          element.after paginationTemplate
])
