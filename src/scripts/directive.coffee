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
        sortable: (if el.attr("sortable") then el.attr("sortable") else false)
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

      # update pagination where parameters changes
      if scope.options.paginationEnabled
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

        headerTemplate = $compile("<thead ng-include=\"templates.header\"></thead>")(scope)
        element.filter("thead").remove()
        tbody = element.find('tbody')
        if (tbody[0]) then $(tbody[0]).before headerTemplate else element.prepend headerTemplate
        element.addClass "ng-table"

        if scope.options.paginationEnabled
          paginationTemplate = $compile("<div ng-include=\"templates.pagination\"></div>")(scope)
          element.after paginationTemplate
])
